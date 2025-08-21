# PowerShell script to set up AndroidBluetoothChat project
# Run in PowerShell: cd C:\Users\sanja\Blueetoothchat; .\setup_bluetooth_chat.ps1

# Set project root
$projectRoot = "C:\Users\sanja\Blueetoothchat\AndroidBluetoothChat"
$javaPath = "$projectRoot\app\src\main\java\com\sanja\bluetoothchat"
$layoutPath = "$projectRoot\app\src\main\res\layout"
$valuesPath = "$projectRoot\app\src\main\res\values"
$fontPath = "$projectRoot\app\src\main\res\font"

# Function to create file with error handling
function Create-File {
    param (
        [string]$Path,
        [string]$Content
    )
    try {
        Set-Content -Path $Path -Value $Content -ErrorAction Stop
        Write-Host "Created $Path"
    } catch {
        Write-Host "Error creating $Path : $_"
    }
}

# Create folder structure
try {
    New-Item -Path $projectRoot -ItemType Directory -Force -ErrorAction Stop
    New-Item -Path $javaPath -ItemType Directory -Force -ErrorAction Stop
    New-Item -Path $layoutPath -ItemType Directory -Force -ErrorAction Stop
    New-Item -Path $valuesPath -ItemType Directory -Force -ErrorAction Stop
    New-Item -Path $fontPath -ItemType Directory -Force -ErrorAction Stop
    New-Item -Path "$projectRoot\app" -ItemType Directory -Force -ErrorAction Stop
    Write-Host "Folder structure created successfully"
} catch {
    Write-Host "Error creating folder structure: $_"
    exit
}

# Create MainActivity.java
$mainActivityContent = @'
package com.sanja.bluetoothchat;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.UUID;

public class MainActivity extends AppCompatActivity {
    private static final UUID APP_UUID = UUID.fromString("fa87c0d0-afac-11de-8a39-800c29f3c000");
    private static final String APP_NAME = "BluetoothChatApp";
    private static final int REQUEST_ENABLE_BT = 1;
    private static final int MESSAGE_READ = 2;
    private static final int MESSAGE_WRITE = 3;
    private static final int MESSAGE_TOAST = 4;

    private BluetoothAdapter bluetoothAdapter;
    private ArrayAdapter<String> devicesAdapter;
    private ArrayList<BluetoothDevice> devicesList;
    private BluetoothService bluetoothService;
    private TextView statusText;
    private EditText messageInput;
    private TextView chatOutput;
    private Button sendButton;

    private final Handler handler = new Handler(Looper.getMainLooper()) {
        @Override
        public void handleMessage(Message msg) {
            switch (msg.what) {
                case MESSAGE_READ:
                    byte[] readBuf = (byte[]) msg.obj;
                    String readMessage = new String(readBuf, 0, msg.arg1);
                    String decryptedMessage = EncryptionUtil.decrypt(readMessage);
                    chatOutput.append("Received: " + decryptedMessage + "\n");
                    break;
                case MESSAGE_WRITE:
                    byte[] writeBuf = (byte[]) msg.obj;
                    String writeMessage = new String(writeBuf);
                    chatOutput.append("Sent: " + writeMessage + "\n");
                    break;
                case MESSAGE_TOAST:
                    Toast.makeText(MainActivity.this, msg.obj.toString(), Toast.LENGTH_SHORT).show();
                    break;
            }
        }
    };

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                if (device != null && device.getName() != null) {
                    devicesList.add(device);
                    devicesAdapter.add(device.getName() + "\n" + device.getAddress());
                }
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
        if (bluetoothAdapter == null) {
            Toast.makeText(this, "Bluetooth not supported", Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        statusText = findViewById(R.id.status_text);
        messageInput = findViewById(R.id.message_input);
        chatOutput = findViewById(R.id.chat_output);
        sendButton = findViewById(R.id.send_button);
        ListView devicesListView = findViewById(R.id.devices_list);
        Button startServerButton = findViewById(R.id.start_server_button);
        Button startClientButton = findViewById(R.id.start_client_button);

        devicesList = new ArrayList<>();
        devicesAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1);
        devicesListView.setAdapter(devicesAdapter);

        if (!bluetoothAdapter.isEnabled()) {
            Intent enableBtIntent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
            startActivityForResult(enableBtIntent, REQUEST_ENABLE_BT);
        }

        startServerButton.setOnClickListener(v -> {
            statusText.setText("Starting server...");
            bluetoothService = new BluetoothService(handler, true);
            bluetoothService.start();
        });

        startClientButton.setOnClickListener(v -> {
            statusText.setText("Discovering devices...");
            devicesAdapter.clear();
            devicesList.clear();
            bluetoothAdapter.startDiscovery();
        });

        devicesListView.setOnItemClickListener((parent, view, position, id) -> {
            bluetoothAdapter.cancelDiscovery();
            BluetoothDevice device = devicesList.get(position);
            statusText.setText("Connecting to " + device.getName() + "...");
            bluetoothService = new BluetoothService(handler, false);
            bluetoothService.connect(device);
        });

        sendButton.setOnClickListener(v -> {
            String message = messageInput.getText().toString();
            if (!message.isEmpty() && bluetoothService != null) {
                String encryptedMessage = EncryptionUtil.encrypt(message);
                bluetoothService.write(encryptedMessage.getBytes());
                messageInput.setText("");
            }
        });

        IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_FOUND);
        registerReceiver(receiver, filter);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_ENABLE_BT && resultCode == RESULT_CANCELED) {
            Toast.makeText(this, "Bluetooth must be enabled", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (bluetoothService != null) {
            bluetoothService.stop();
        }
        unregisterReceiver(receiver);
    }
}
'@
Create-File -Path "$javaPath\MainActivity.java" -Content $mainActivityContent

# Create BluetoothService.java
$bluetoothServiceContent = @'
package com.sanja.bluetoothchat;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothServerSocket;
import android.bluetooth.BluetoothSocket;
import android.os.Handler;
import android.os.Message;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.UUID;

public class BluetoothService {
    private static final UUID APP_UUID = UUID.fromString("fa87c0d0-afac-11de-8a39-800c29f3c000");
    private static final String APP_NAME = "BluetoothChatApp";
    private final BluetoothAdapter bluetoothAdapter;
    private final Handler handler;
    private AcceptThread acceptThread;
    private ConnectThread connectThread;
    private ConnectedThread connectedThread;
    private int state;
    private static final int STATE_NONE = 0;
    private static final int STATE_LISTEN = 1;
    private static final int STATE_CONNECTING = 2;
    private static final int STATE_CONNECTED = 3;

    public BluetoothService(Handler handler, boolean isServer) {
        this.bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
        this.handler = handler;
        this.state = STATE_NONE;
        if (isServer) {
            start();
        }
    }

    private synchronized void setState(int state) {
        this.state = state;
    }

    public synchronized int getState() {
        return state;
    }

    public synchronized void start() {
        if (connectThread != null) {
            connectThread.cancel();
            connectThread = null;
        }
        if (connectedThread != null) {
            connectedThread.cancel();
            connectedThread = null;
        }
        if (acceptThread == null) {
            acceptThread = new AcceptThread();
            acceptThread.start();
        }
        setState(STATE_LISTEN);
    }

    public synchronized void connect(BluetoothDevice device) {
        if (state == STATE_CONNECTING) {
            if (connectThread != null) {
                connectThread.cancel();
                connectThread = null;
            }
        }
        if (connectedThread != null) {
            connectedThread.cancel();
            connectedThread = null;
        }
        connectThread = new ConnectThread(device);
        connectThread.start();
        setState(STATE_CONNECTING);
    }

    public synchronized void connected(BluetoothSocket socket, BluetoothDevice device) {
        if (acceptThread != null) {
            acceptThread.cancel();
            acceptThread = null;
        }
        if (connectThread != null) {
            connectThread.cancel();
            connectThread = null;
        }
        if (connectedThread != null) {
            connectedThread.cancel();
            connectedThread = null;
        }
        connectedThread = new ConnectedThread(socket);
        connectedThread.start();
        Message msg = handler.obtainMessage(MainActivity.MESSAGE_TOAST);
        msg.obj = "Connected to " + device.getName();
        handler.sendMessage(msg);
        setState(STATE_CONNECTED);
    }

    public synchronized void stop() {
        if (connectThread != null) {
            connectThread.cancel();
            connectThread = null;
        }
        if (connectedThread != null) {
            connectedThread.cancel();
            connectedThread = null;
        }
        if (acceptThread != null) {
            acceptThread.cancel();
            acceptThread = null;
        }
        setState(STATE_NONE);
    }

    public void write(byte[] out) {
        ConnectedThread r;
        synchronized (this) {
            if (state != STATE_CONNECTED) return;
            r = connectedThread;
        }
        r.write(out);
    }

    private void connectionFailed() {
        Message msg = handler.obtainMessage(MainActivity.MESSAGE_TOAST);
        msg.obj = "Connection failed";
        handler.sendMessage(msg);
        BluetoothService.this.start();
    }

    private void connectionLost() {
        Message msg = handler.obtainMessage(MainActivity.MESSAGE_TOAST);
        msg.obj = "Connection lost";
        handler.sendMessage(msg);
        BluetoothService.this.start();
    }

    private class AcceptThread extends Thread {
        private final BluetoothServerSocket serverSocket;

        public AcceptThread() {
            BluetoothServerSocket tmp = null;
            try {
                tmp = bluetoothAdapter.listenUsingRfcommWithServiceRecord(APP_NAME, APP_UUID);
            } catch (IOException e) {
                handler.obtainMessage(MainActivity.MESSAGE_TOAST, -1, -1, "Server socket failed").sendToTarget();
            }
            serverSocket = tmp;
        }

        public void run() {
            setName("AcceptThread");
            BluetoothSocket socket;
            while (state != STATE_CONNECTED) {
                try {
                    socket = serverSocket.accept();
                } catch (IOException e) {
                    connectionFailed();
                    break;
                }
                if (socket != null) {
                    synchronized (BluetoothService.this) {
                        switch (state) {
                            case STATE_LISTEN:
                            case STATE_CONNECTING:
                                connected(socket, socket.getRemoteDevice());
                                break;
                            case STATE_NONE:
                            case STATE_CONNECTED:
                                try {
                                    socket.close();
                                } catch (IOException e) {
                                    // Ignore
                                }
                                break;
                        }
                    }
                }
            }
        }

        public void cancel() {
            try {
                serverSocket.close();
            } catch (IOException e) {
                // Ignore
            }
        }
    }

    private class ConnectThread extends Thread {
        private final BluetoothSocket socket;
        private final BluetoothDevice device;

        public ConnectThread(BluetoothDevice device) {
            this.device = device;
            BluetoothSocket tmp = null;
            try {
                tmp = device.createRfcommSocketToServiceRecord(APP_UUID);
            } catch (IOException e) {
                handler.obtainMessage(MainActivity.MESSAGE_TOAST, -1, -1, "Client socket failed").sendToTarget();
            }
            socket = tmp;
        }

        public void run() {
            bluetoothAdapter.cancelDiscovery();
            try {
                socket.connect();
            } catch (IOException e) {
                try {
                    socket.close();
                } catch (IOException e2) {
                    // Ignore
                }
                connectionFailed();
                return;
            }
            synchronized (BluetoothService.this) {
                connectThread = null;
            }
            connected(socket, device);
        }

        public void cancel() {
            try {
                socket.close();
            } catch (IOException e) {
                // Ignore
            }
        }
    }

    private class ConnectedThread extends Thread {
        private final BluetoothSocket socket;
        private final InputStream inputStream;
        private final OutputStream outputStream;

        public ConnectedThread(BluetoothSocket socket) {
            this.socket = socket;
            InputStream tmpIn = null;
            OutputStream tmpOut = null;
            try {
                tmpIn = socket.getInputStream();
                tmpOut = socket.getOutputStream();
            } catch (IOException e) {
                handler.obtainMessage(MainActivity.MESSAGE_TOAST, -1, -1, "Stream error").sendToTarget();
            }
            inputStream = tmpIn;
            outputStream = tmpOut;
        }

        public void run() {
            byte[] buffer = new byte[1024];
            int bytes;
            while (true) {
                try {
                    bytes = inputStream.read(buffer);
                    handler.obtainMessage(MainActivity.MESSAGE_READ, bytes, -1, buffer).sendToTarget();
                } catch (IOException e) {
                    connectionLost();
                    break;
                }
            }
        }

        public void write(byte[] buffer) {
            try {
                outputStream.write(buffer);
                handler.obtainMessage(MainActivity.MESSAGE_WRITE, -1, -1, buffer).sendToTarget();
            } catch (IOException e) {
                handler.obtainMessage(MainActivity.MESSAGE_TOAST, -1, -1, "Write error").sendToTarget();
            }
        }

        public void cancel() {
            try {
                socket.close();
            } catch (IOException e) {
                // Ignore
            }
        }
    }
}
'@
Create-File -Path "$javaPath\BluetoothService.java" -Content $bluetoothServiceContent

# Create EncryptionUtil.java
$encryptionUtilContent = @'
package com.sanja.bluetoothchat;

import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.spec.SecretKeySpec;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PublicKey;
import java.util.Base64;

public class EncryptionUtil {
    private static final String ALGORITHM = "AES";
    private static SecretKeySpec aesKey;

    public static void performKeyExchange(PublicKey clientPublicKey, PublicKey serverPublicKey) throws Exception {
        KeyPairGenerator keyPairGen = KeyPairGenerator.getInstance("DH");
        keyPairGen.initialize(2048);
        KeyPair clientKeyPair = keyPairGen.generateKeyPair();
        KeyPair serverKeyPair = keyPairGen.generateKeyPair();

        KeyAgreement clientKeyAgree = KeyAgreement.getInstance("DH");
        clientKeyAgree.init(clientKeyPair.getPrivate());
        clientKeyAgree.doPhase(serverPublicKey, true);
        byte[] clientSharedSecret = clientKeyAgree.generateSecret();

        KeyAgreement serverKeyAgree = KeyAgreement.getInstance("DH");
        serverKeyAgree.init(serverKeyPair.getPrivate());
        serverKeyAgree.doPhase(clientPublicKey, true);
        byte[] serverSharedSecret = serverKeyAgree.generateSecret();

        aesKey = new SecretKeySpec(clientSharedSecret, 0, 16, ALGORITHM);
    }

    public static String encrypt(String message) {
        try {
            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.ENCRYPT_MODE, aesKey);
            byte[] encrypted = cipher.doFinal(message.getBytes());
            return Base64.getEncoder().encodeToString(encrypted);
        } catch (Exception e) {
            e.printStackTrace();
            return message;
        }
    }

    public static String decrypt(String encryptedMessage) {
        try {
            Cipher crypt = Cipher.getInstance(ALGORITHM);
            crypt.init(Cipher.DECRYPT_MODE, aesKey);
            byte[] decoded = Base64.getDecoder().decode(encryptedMessage);
            byte[] decrypted = crypt.doFinal(decoded);
            return new String(decrypted);
        } catch (Exception e) {
            e.printStackTrace();
            return encryptedMessage;
        }
    }
}
'@
Create-File -Path "$javaPath\EncryptionUtil.java" -Content $encryptionUtilContent

# Create activity_main.xml
$activityMainContent = @'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp"
    android:background="#FFE0F7FA">

    <TextView
        android:id="@+id/status_text"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Status: Idle"
        android:textSize="18sp"
        android:textColor="#FF0277BD"
        android:padding="8dp"/>

    <Button
        android:id="@+id/start_server_button"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Start Server"
        android:backgroundTint="#FF0288D1"
        android:textColor="#FFFFFF"
        android:layout_marginBottom="8dp"/>

    <Button
        android:id="@+id/start_client_button"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Start Client"
        android:backgroundTint="#FF0288D1"
        android:textColor="#FFFFFF"
        android:layout_marginBottom="8dp"/>

    <ListView
        android:id="@+id/devices_list"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="#FFFFFF"
        android:layout_marginBottom="8dp"/>

    <EditText
        android:id="@+id/message_input"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:hint="Type a message"
        android:background="#FFFFFF"
        android:padding="8dp"
        android:layout_marginBottom="8dp"/>

    <Button
        android:id="@+id/send_button"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Send"
        android:backgroundTint="#FF0288D1"
        android:textColor="#FFFFFF"/>

    <TextView
        android:id="@+id/chat_output"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:background="#FFFFFF"
        android:padding="8dp"
        android:textColor="#FF01579B"
        android:layout_marginTop="8dp"/>

</LinearLayout>
'@
Create-File -Path "$layoutPath\activity_main.xml" -Content $activityMainContent

# Create AndroidManifest.xml
$manifestContent = @'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.sanja.bluetoothchat">
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
    <uses-feature android:name="android.hardware.bluetooth" android:required="true"/>
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
'@
Create-File -Path "$projectRoot\app\src\main\AndroidManifest.xml" -Content $manifestContent

# Create app/build.gradle
$appBuildGradleContent = @'
apply plugin: 'com.android.application'

android {
    compileSdkVersion 34
    defaultConfig {
        applicationId "com.sanja.bluetoothchat"
        minSdkVersion 23
        targetSdkVersion 34
        versionCode 1
        versionName "1.0"
    }
    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
}
'@
Create-File -Path "$projectRoot\app\build.gradle" -Content $appBuildGradleContent

# Create project build.gradle
$projectBuildGradleContent = @'
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.5.2'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
'@
Create-File -Path "$projectRoot\build.gradle" -Content $projectBuildGradleContent

# Create settings.gradle
$settingsGradleContent = @'
include ':app'
'@
Create-File -Path "$projectRoot\settings.gradle" -Content $settingsGradleContent

# Create strings.xml
$stringsContent = @'
<resources>
    <string name="app_name">Bluetooth Chat</string>
</resources>
'@
Create-File -Path "$valuesPath\strings.xml" -Content $stringsContent

# Create font resource for Poppins
$fontContent = @'
<font-family xmlns:android="http://schemas.android.com/apk/res/android">
    <font android:font="@assets/fonts/Poppins-Regular.ttf"/>
</font-family>
'@
Create-File -Path "$fontPath\poppins_regular.xml" -Content $fontContent

# Print completion message
Write-Host "AndroidBluetoothChat project created at $projectRoot"
Write-Host "Next steps:"
Write-Host "1. Download Poppins-Regular.ttf from https://fonts.google.com/specimen/Poppins and place in $projectRoot\app\src\main\assets\fonts\"
Write-Host "2. Open Android Studio, select 'Open an existing project', choose $projectRoot"
Write-Host "3. Sync project, build, and deploy to Android phones"
