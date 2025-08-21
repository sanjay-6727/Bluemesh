import javax.bluetooth.*;
import javax.microedition.io.*;
import java.io.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Scanner;
import java.util.Set;
import javax.crypto.*;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.Base64;

public class ImprovedBluetoothChatApp {
    private static final javax.bluetooth.UUID APP_UUID = new javax.bluetooth.UUID("fa87c0d0afac11de8a39800c29f3c000", false);
    private static final String APP_NAME = "ImprovedBluetoothChatApp";
    private static LocalDevice localDevice;
    private static DiscoveryAgent discoveryAgent;
    private static StreamConnectionNotifier notifier;
    private static final List<RemoteDevice> connectedDevices = new ArrayList<>();
    private static final Map<RemoteDevice, DataOutputStream> outputStreams = new HashMap<>();
    private static final Map<RemoteDevice, DataInputStream> inputStreams = new HashMap<>();
    private static final Set<String> seenMessages = new HashSet<>();
    private static KeyPair dhKeyPair;
    private static SecretKeySpec aesKey;
    private static volatile boolean running = true;

    public static void main(String[] args) {
        Scanner scanner = new Scanner(System.in);
        System.out.println("Improved Bluetooth Chat App");
        System.out.println("1. Start Server");
        System.out.println("2. Start Client");
        System.out.print("Choose an option (1 or 2): ");
        int choice = scanner.nextInt();
        scanner.nextLine(); // Consume newline

        try {
            localDevice = LocalDevice.getLocalDevice();
            discoveryAgent = localDevice.getDiscoveryAgent();
            System.out.println("Local Device: " + getFriendlyNameSafe(localDevice));
            initializeDiffieHellman();

            if (choice == 1) {
                startServer();
            } else if (choice == 2) {
                startClient(scanner);
            } else {
                System.out.println("Invalid option.");
            }
        } catch (BluetoothStateException | NoSuchAlgorithmException | InvalidKeyException e) {
            System.err.println("Initialization failed: " + e.getMessage());
        } finally {
            scanner.close();
        }
    }

    private static String getFriendlyNameSafe(LocalDevice device) {
        try {
            return device.getFriendlyName();
        } catch (Exception e) {
            return "Unknown Device";
        }
    }

    private static String getFriendlyNameSafe(RemoteDevice device) {
        try {
            return device.getFriendlyName(false);
        } catch (IOException e) {
            return "Unknown Device";
        }
    }

    private static void initializeDiffieHellman() throws NoSuchAlgorithmException, InvalidKeyException {
        KeyPairGenerator keyPairGen = KeyPairGenerator.getInstance("DH");
        keyPairGen.initialize(2048);
        dhKeyPair = keyPairGen.generateKeyPair();
    }

    private static void startServer() {
        try {
            String url = "btspp://localhost:" + APP_UUID + ";name=" + APP_NAME;
            notifier = (StreamConnectionNotifier) Connector.open(url);
            System.out.println("Server started. Waiting for connections...");

            new Thread(() -> {
                while (running) {
                    try {
                        StreamConnection connection = notifier.acceptAndOpen();
                        RemoteDevice device = RemoteDevice.getRemoteDevice(connection);
                        System.out.println("Client connected: " + getFriendlyNameSafe(device));
                        handleNewConnection(connection, device);
                    } catch (IOException e) {
                        if (running) System.err.println("Server connection error: " + e.getMessage());
                    }
                }
            }).start();
        } catch (IOException e) {
            System.err.println("Server setup failed: " + e.getMessage());
        }
    }

    private static void startClient(Scanner scanner) {
        try {
            System.out.println("Starting device discovery...");
            List<RemoteDevice> devices = new ArrayList<>();
            DeviceDiscoveryListener listener = new DeviceDiscoveryListener(devices);
            discoveryAgent.startInquiry(DiscoveryAgent.GIAC, listener);
            synchronized (listener) {
                listener.wait();
            }

            if (devices.isEmpty()) {
                System.out.println("No devices found.");
                return;
            }

            System.out.println("Discovered devices:");
            for (int i = 0; i < devices.size(); i++) {
                System.out.println((i + 1) + ". " + getFriendlyNameSafe(devices.get(i)));
            }
            System.out.print("Select device (1-" + devices.size() + "): ");
            int deviceIndex = scanner.nextInt() - 1;
            scanner.nextLine(); // Consume newline

            if (deviceIndex < 0 || deviceIndex >= devices.size()) {
                System.out.println("Invalid device selection.");
                return;
            }

            RemoteDevice selectedDevice = devices.get(deviceIndex);
            String url = discoverService(selectedDevice);
            if (url == null) {
                System.out.println("No chat service found on selected device.");
                return;
            }

            StreamConnection connection = (StreamConnection) Connector.open(url);
            System.out.println("Connected to " + getFriendlyNameSafe(selectedDevice));
            handleNewConnection(connection, selectedDevice);
        } catch (BluetoothStateException e) {
            System.err.println("Bluetooth discovery error: " + e.getMessage());
        } catch (IOException e) {
            System.err.println("Client connection error: " + e.getMessage());
        } catch (InterruptedException e) {
            System.err.println("Discovery interrupted: " + e.getMessage());
        }
    }

    private static String discoverService(RemoteDevice device) throws BluetoothStateException, InterruptedException {
        javax.bluetooth.UUID[] uuidSet = { APP_UUID };
        ServiceDiscoveryListener listener = new ServiceDiscoveryListener();
        discoveryAgent.searchServices(null, uuidSet, device, listener);
        synchronized (listener) {
            listener.wait();
        }
        return listener.getServiceURL();
    }

    private static void handleNewConnection(StreamConnection connection, RemoteDevice device) {
        try {
            DataInputStream input = new DataInputStream(connection.openInputStream());
            DataOutputStream output = new DataOutputStream(connection.openOutputStream());

            // Perform Diffie-Hellman key exchange
            ObjectOutputStream oos = new ObjectOutputStream(output);
            oos.writeObject(dhKeyPair.getPublic());
            oos.flush();
            ObjectInputStream ois = new ObjectInputStream(input);
            PublicKey remotePublicKey = (PublicKey) ois.readObject();

            KeyAgreement keyAgreement = KeyAgreement.getInstance("DH");
            keyAgreement.init(dhKeyPair.getPrivate());
            keyAgreement.doPhase(remotePublicKey, true);
            byte[] sharedSecret = keyAgreement.generateSecret();
            aesKey = new SecretKeySpec(Arrays.copyOf(sharedSecret, 16), "AES");

            synchronized (connectedDevices) {
                connectedDevices.add(device);
                inputStreams.put(device, input);
                outputStreams.put(device, output);
            }

            new Thread(() -> {
                try {
                    while (running) {
                        String message = input.readUTF();
                        handleMessage(message, device);
                    }
                } catch (IOException e) {
                    if (running) System.err.println("Communication error with " + getFriendlyNameSafe(device) + ": " + e.getMessage());
                } finally {
                    cleanupDevice(device);
                }
            }).start();

            if (connectedDevices.size() == 1) {
                startUserInput();
            }
        } catch (IOException e) {
            System.err.println("Connection setup error with " + getFriendlyNameSafe(device) + ": " + e.getMessage());
        } catch (GeneralSecurityException e) {
            System.err.println("Security error with " + getFriendlyNameSafe(device) + ": " + e.getMessage());
        } catch (ClassNotFoundException e) {
            System.err.println("Key exchange error with " + getFriendlyNameSafe(device) + ": " + e.getMessage());
        }
    }

    private static void handleMessage(String message, RemoteDevice sender) throws IOException {
        try {
            String[] parts = message.split(":", 2);
            if (parts.length != 2) {
                System.err.println("Invalid message format from " + getFriendlyNameSafe(sender));
                return;
            }
            String msgId = parts[0];
            String encryptedMsg = parts[1];

            synchronized (seenMessages) {
                if (seenMessages.contains(msgId)) {
                    return;
                }
                seenMessages.add(msgId);
            }

            String decrypted = decrypt(encryptedMsg);
            System.out.println("Received from " + getFriendlyNameSafe(sender) + ": " + decrypted);
            forwardToAll(encryptedMsg, msgId, sender);
        } catch (GeneralSecurityException e) {
            System.err.println("Decryption error: " + e.getMessage());
        }
    }

    private static void forwardToAll(String encryptedMsg, String msgId, RemoteDevice sender) {
        String fullMsg = msgId + ":" + encryptedMsg;
        synchronized (connectedDevices) {
            for (RemoteDevice device : connectedDevices) {
                if (!device.equals(sender)) {
                    try {
                        DataOutputStream out = outputStreams.get(device);
                        out.writeUTF(fullMsg);
                        out.flush();
                    } catch (IOException e) {
                        System.err.println("Error forwarding to " + getFriendlyNameSafe(device) + ": " + e.getMessage());
                    }
                }
            }
        }
    }

    private static void startUserInput() {
        Scanner scanner = new Scanner(System.in);
        System.out.println("Enter messages to send (type 'exit' to quit):");
        while (running) {
            String message = scanner.nextLine();
            if ("exit".equalsIgnoreCase(message)) {
                shutdown();
                break;
            }
            try {
                String msgId = generateMsgId(message);
                String encrypted = encrypt(message);
                String fullMsg = msgId + ":" + encrypted;
                synchronized (connectedDevices) {
                    for (DataOutputStream out : outputStreams.values()) {
                        out.writeUTF(fullMsg);
                        out.flush();
                    }
                }
                System.out.println("Sent: " + message);
            } catch (IOException e) {
                System.err.println("Error sending message: " + e.getMessage());
            } catch (GeneralSecurityException e) {
                System.err.println("Encryption error: " + e.getMessage());
            }
        }
        scanner.close();
    }

    private static String generateMsgId(String msg) throws NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        String input = msg + System.currentTimeMillis();
        byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(hash);
    }

    private static String encrypt(String message) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        byte[] iv = new byte[16];
        new SecureRandom().nextBytes(iv);
        IvParameterSpec ivSpec = new IvParameterSpec(iv);
        cipher.init(Cipher.ENCRYPT_MODE, aesKey, ivSpec);
        byte[] encrypted = cipher.doFinal(message.getBytes(StandardCharsets.UTF_8));
        byte[] combined = new byte[iv.length + encrypted.length];
        System.arraycopy(iv, 0, combined, 0, iv.length);
        System.arraycopy(encrypted, 0, combined, iv.length, encrypted.length);
        return Base64.getEncoder().encodeToString(combined);
    }

    private static String decrypt(String encryptedMessage) throws GeneralSecurityException {
        byte[] decoded = Base64.getDecoder().decode(encryptedMessage);
        byte[] iv = Arrays.copyOfRange(decoded, 0, 16);
        byte[] encrypted = Arrays.copyOfRange(decoded, 16, decoded.length);
        Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        cipher.init(Cipher.DECRYPT_MODE, aesKey, new IvParameterSpec(iv));
        byte[] decrypted = cipher.doFinal(encrypted);
        return new String(decrypted, StandardCharsets.UTF_8);
    }

    private static void cleanupDevice(RemoteDevice device) {
        synchronized (connectedDevices) {
            try {
                DataInputStream in = inputStreams.remove(device);
                DataOutputStream out = outputStreams.remove(device);
                if (in != null) in.close();
                if (out != null) out.close();
                connectedDevices.remove(device);
                System.out.println("Disconnected: " + getFriendlyNameSafe(device));
            } catch (IOException e) {
                System.err.println("Error cleaning up device " + getFriendlyNameSafe(device) + ": " + e.getMessage());
            }
        }
    }

    private static void shutdown() {
        running = false;
        try {
            synchronized (connectedDevices) {
                for (RemoteDevice device : new ArrayList<>(connectedDevices)) {
                    cleanupDevice(device);
                }
            }
            if (notifier != null) {
                notifier.close();
            }
        } catch (IOException e) {
            System.err.println("Shutdown error: " + e.getMessage());
        }
        System.exit(0);
    }
}

class DeviceDiscoveryListener implements DiscoveryListener {
    private final List<RemoteDevice> devices;

    public DeviceDiscoveryListener(List<RemoteDevice> devices) {
        this.devices = devices;
    }

    @Override
    public void deviceDiscovered(RemoteDevice btDevice, DeviceClass cod) {
        devices.add(btDevice);
    }

    @Override
    public void inquiryCompleted(int discType) {
        synchronized (this) {
            notify();
        }
    }

    @Override
    public void servicesDiscovered(int transID, ServiceRecord[] servRecord) {}

    @Override
    public void serviceSearchCompleted(int transID, int respCode) {}
}

class ServiceDiscoveryListener implements DiscoveryListener {
    private String serviceURL;

    public String getServiceURL() {
        return serviceURL;
    }

    @Override
    public void deviceDiscovered(RemoteDevice btDevice, DeviceClass cod) {}

    @Override
    public void inquiryCompleted(int discType) {}

    @Override
    public void servicesDiscovered(int transID, ServiceRecord[] servRecord) {
        for (ServiceRecord record : servRecord) {
            String url = record.getConnectionURL(ServiceRecord.NOAUTHENTICATE_NOENCRYPT, false);
            if (url != null) {
                serviceURL = url;
                break;
            }
        }
    }

    @Override
    public void serviceSearchCompleted(int transID, int respCode) {
        synchronized (this) {
            notify();
        }
    }
}