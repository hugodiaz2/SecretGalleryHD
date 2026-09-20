package com.example.secret_gallery;

import java.io.*;
import java.security.MessageDigest;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Compatible with encrypt 5.x: IV(16) + AES-SIC/CTR with PKCS7 padding.
 * File transfers use bounded buffers; previews may return in-memory bytes.
 * No provider is hardcoded: Android selects its optimized implementation.
 */
public final class VaultCrypto {
    private static final int BUFFER = 128 * 1024;

    public static final class Result {
        public final String digest;
        public final long length;
        Result(String digest, long length) { this.digest = digest; this.length = length; }
    }

    private static Cipher cipher(int mode, byte[] key, byte[] iv) throws Exception {
        if (key.length != 32 || iv.length != 16) throw new IOException("Invalid key or IV");
        Cipher cipher = Cipher.getInstance("AES/CTR/NoPadding");
        cipher.init(mode, new SecretKeySpec(key, "AES"), new IvParameterSpec(iv));
        return cipher;
    }

    private static String hex(byte[] bytes) {
        char[] chars = new char[bytes.length * 2];
        final char[] alphabet = "0123456789abcdef".toCharArray();
        for (int i = 0; i < bytes.length; i++) {
            chars[i * 2] = alphabet[(bytes[i] & 255) >>> 4];
            chars[i * 2 + 1] = alphabet[bytes[i] & 15];
        }
        return new String(chars);
    }

    public static String hash(File source) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[BUFFER];
        try (InputStream input = new FileInputStream(source)) {
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        return hex(digest.digest());
    }

    private static void reserveOutput(File source, File target) throws IOException {
        if (source.getCanonicalFile().equals(target.getCanonicalFile()) || !target.createNewFile()) {
            throw new IOException("Output already exists or aliases source");
        }
    }

    public static void encrypt(File source, File target, byte[] key, byte[] iv) throws Exception {
        Cipher cipher = cipher(Cipher.ENCRYPT_MODE, key, iv);
        reserveOutput(source, target);
        boolean complete = false;
        try {
            try (InputStream input = new FileInputStream(source);
                 FileOutputStream raw = new FileOutputStream(target);
                 BufferedOutputStream output = new BufferedOutputStream(raw, BUFFER)) {
                output.write(iv);
                byte[] buffer = new byte[BUFFER];
                long length = 0;
                int count;
                while ((count = input.read(buffer)) != -1) {
                    length += count;
                    byte[] encrypted = cipher.update(buffer, 0, count);
                    if (encrypted != null) output.write(encrypted);
                }
                int pad = 16 - (int)(length % 16);
                byte[] padding = new byte[pad];
                Arrays.fill(padding, (byte)pad);
                output.write(cipher.doFinal(padding));
                output.flush();
                raw.getFD().sync();
            }
            complete = true;
        } finally {
            if (!complete) target.delete();
        }
    }

    public static Result decrypt(File source, File target, byte[] key) throws Exception {
        long size = source.length();
        if (size < 32 || (size - 16) % 16 != 0) throw new IOException("Invalid encrypted length");
        // Read and validate the header before creating a destination.
        try (DataInputStream input = new DataInputStream(new FileInputStream(source))) {
            byte[] iv = new byte[16];
            input.readFully(iv);
            Cipher cipher = cipher(Cipher.DECRYPT_MODE, key, iv);
            if (target != null) reserveOutput(source, target);
            boolean complete = false;
            try {
                Result result;
                try (FileOutputStream raw = target == null ? null : new FileOutputStream(target);
                     BufferedOutputStream output = raw == null ? null : new BufferedOutputStream(raw, BUFFER)) {
                    PlainSink sink = new PlainSink(output);
                    byte[] buffer = new byte[BUFFER];
                    int count;
                    while ((count = input.read(buffer)) != -1) sink.accept(cipher.update(buffer, 0, count));
                    sink.accept(cipher.doFinal());
                    result = sink.finish();
                    if (output != null) {
                        output.flush();
                        raw.getFD().sync();
                    }
                }
                complete = true;
                return result;
            } finally {
                if (!complete && target != null) target.delete();
            }
        }
    }

    /** In-memory preview input; no unencrypted temporary file is created. */
    public static byte[] decryptBytes(File source, byte[] key) throws Exception {
        long size = source.length();
        if (size < 32 || (size - 16) % 16 != 0 || size - 16 > Integer.MAX_VALUE) {
            throw new IOException("Invalid encrypted length");
        }
        try (DataInputStream input = new DataInputStream(new FileInputStream(source));
             ByteArrayOutputStream output = new ByteArrayOutputStream((int)(size - 16))) {
            byte[] iv = new byte[16];
            input.readFully(iv);
            Cipher cipher = cipher(Cipher.DECRYPT_MODE, key, iv);
            PlainSink sink = new PlainSink(output);
            byte[] buffer = new byte[BUFFER];
            int count;
            while ((count = input.read(buffer)) != -1) sink.accept(cipher.update(buffer, 0, count));
            sink.accept(cipher.doFinal());
            sink.finish();
            return output.toByteArray();
        }
    }
    /** Holds the final block until PKCS7 has been checked. */
    private static final class PlainSink {
        private final OutputStream output;
        private final MessageDigest digest = MessageDigest.getInstance("SHA-256");
        private byte[] tail = new byte[0];
        private long length = 0;
        PlainSink(OutputStream output) throws Exception { this.output = output; }
        void accept(byte[] bytes) throws IOException {
            if (bytes == null || bytes.length == 0) return;
            byte[] joined = new byte[tail.length + bytes.length];
            System.arraycopy(tail, 0, joined, 0, tail.length);
            System.arraycopy(bytes, 0, joined, tail.length, bytes.length);
            int count = Math.max(0, joined.length - 16);
            emit(joined, count);
            tail = Arrays.copyOfRange(joined, count, joined.length);
        }
        private void emit(byte[] bytes, int count) throws IOException {
            if (output != null) output.write(bytes, 0, count);
            digest.update(bytes, 0, count);
            length += count;
        }
        Result finish() throws IOException {
            if (tail.length != 16) throw new IOException("Missing final block");
            int pad = tail[15] & 255;
            if (pad < 1 || pad > 16) throw new IOException("Invalid padding");
            for (int i = 16 - pad; i < 16; i++) {
                if ((tail[i] & 255) != pad) throw new IOException("Invalid padding");
            }
            emit(tail, 16 - pad);
            return new Result(hex(digest.digest()), length);
        }
    }
}