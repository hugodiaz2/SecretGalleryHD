package com.example.secret_gallery;

import java.io.*;
import java.nio.file.Files;
import java.util.Arrays;

/** Standalone JVM compatibility check; all inputs are synthetic disposable data. */
public final class VaultCryptoCompatibilityCheck {
    public static void main(String[] args) throws Exception {
        File root = new File(args[0]);
        File output = Files.createTempDirectory(root.toPath(), "native-check-").toFile();
        byte[] key = Files.readAllBytes(new File(root, "key.bin").toPath());
        byte[] iv = Files.readAllBytes(new File(root, "iv.bin").toPath());
        int[] sizes = {1, 15, 16, 17, 31, 131071, 131072, 131073, 1048576};
        for (int size : sizes) {
            File plain = new File(root, size + ".plain");
            File dart = new File(root, size + ".dart.enc");
            File nativeFile = new File(output, size + ".native.enc");
            VaultCrypto.encrypt(plain, nativeFile, key, iv);
            check(Arrays.equals(Files.readAllBytes(dart.toPath()), Files.readAllBytes(nativeFile.toPath())),
                "Dart/native ciphertext mismatch: " + size);
            check(Arrays.equals(Files.readAllBytes(plain.toPath()), VaultCrypto.decryptBytes(dart, key)), "Preview bytes mismatch: " + size);
            File restored = new File(output, size + ".restored");
            VaultCrypto.Result result = VaultCrypto.decrypt(dart, restored, key);
            check(Arrays.equals(Files.readAllBytes(plain.toPath()), Files.readAllBytes(restored.toPath())),
                "Restored bytes mismatch: " + size);
            check(result.length == size && result.digest.equals(VaultCrypto.hash(plain)), "Hash mismatch");
            check(VaultCrypto.decrypt(dart, null, key).digest.equals(result.digest), "Verify-only mismatch");
            boolean refusedOverwrite = false;
            try { VaultCrypto.encrypt(plain, nativeFile, key, iv); }
            catch (IOException expected) { refusedOverwrite = true; }
            check(refusedOverwrite, "Must not overwrite an existing output");
        }
        byte[] corrupt = Files.readAllBytes(new File(root, "17.dart.enc").toPath());
        corrupt[corrupt.length - 1] ^= 15; // Force PKCS7 last plaintext byte to zero.
        File broken = new File(output, "bad.enc");
        Files.write(broken.toPath(), corrupt);
        File partial = new File(output, "must-not-remain");
        boolean rejected = false;
        try { VaultCrypto.decrypt(broken, partial, key); }
        catch (IOException expected) { rejected = true; }
        check(rejected && !partial.exists(), "Invalid padding must remove partial output");
        rejected = false;
        try { VaultCrypto.decryptBytes(broken, key); }
        catch (IOException expected) { rejected = true; }
        check(rejected, "Preview must reject invalid padding");
        File truncated = new File(output, "truncated.enc");
        Files.write(truncated.toPath(), Arrays.copyOf(corrupt, corrupt.length - 1));
        rejected = false;
        try { VaultCrypto.decrypt(truncated, null, key); }
        catch (IOException expected) { rejected = true; }
        check(rejected, "Truncation must be rejected");
        System.out.println("PASS: 9 Dart/native vectors, preview bytes, hashes, counter carry, padding, no-overwrite and failure cleanup.");
    }
    private static void check(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }
}