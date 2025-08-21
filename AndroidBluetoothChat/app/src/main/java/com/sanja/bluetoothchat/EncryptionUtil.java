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
