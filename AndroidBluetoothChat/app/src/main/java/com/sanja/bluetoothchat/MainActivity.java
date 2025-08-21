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
