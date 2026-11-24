// SPDX-License-Identifier: Apache-2.0
// Windows test host for the same C ABI used by Swift. Not an iOS crypto substitute.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Security;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

public static class NativeInteropTests
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int Verify(IntPtr context, IntPtr pin, IntPtr cert, nuint certLen, IntPtr sig, nuint sigLen, IntPtr transcript);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int Sign(IntPtr context, IntPtr transcript, IntPtr output);
    [StructLayout(LayoutKind.Sequential)]
    struct Callbacks { public IntPtr context, verify, sign; }
    [StructLayout(LayoutKind.Sequential)]
    struct Registration {
        public uint architecture, version, platform;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 48)] public byte[] mesh;
        public IntPtr name;
        public nuint nameLen;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Lengths { public nuint identity, info; }
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr mc_new(byte[] tls, byte[] pin, byte[] nonce, byte[] cert, nuint certLen, Callbacks callbacks);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern nint mc_hello(IntPtr handle, [Out] byte[] output, nuint capacity);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern int mc_receive(IntPtr handle, byte[] frame, nuint length);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern int mc_register(IntPtr handle, ref Registration registration, [Out] byte[] proof, nuint proofCap, [Out] byte[] info, nuint infoCap, out Lengths lengths);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern void mc_free(IntPtr handle);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr mc_share_new(IntPtr client, uint rights);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern int mc_share_event(IntPtr share, uint action);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern void mc_share_free(IntPtr share);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr mc_quality_new();
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern uint mc_quality_observe(IntPtr handle, uint milliseconds, uint bytes);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern void mc_quality_free(IntPtr handle);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern int mc_transfer_next(uint total, uint offset, uint chunk);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr mc_transfer_new(uint total);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern int mc_transfer_approve(IntPtr handle);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern int mc_transfer_chunk(IntPtr handle, uint offset, uint chunk);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern void mc_transfer_free(IntPtr handle);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern nint mc_build_tbs(byte[] key, nuint keyLen, byte[] serial, byte[] before, byte[] after, [Out] byte[] output, nuint capacity);
    [DllImport("meshcentral_ios_bridge", CallingConvention = CallingConvention.Cdecl)]
    static extern nint mc_finish_certificate(byte[] tbs, nuint tbsLen, byte[] signature, nuint signatureLen, [Out] byte[] output, nuint capacity);

    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static byte[] Read(IntPtr pointer, int count) { var data = new byte[count]; Marshal.Copy(pointer, data, 0, count); return data; }
    static string NodeID(RSA key) => Convert.ToBase64String(SHA384.HashData(key.ExportRSAPublicKey())).Replace('+', '@').Replace('/', '$');

    sealed class Identity : IDisposable {
        public readonly RSA key = RSA.Create(3072);
        public readonly byte[] certificate;
        public bool corruptSignature;
        public int signatures, verifications;
        readonly Verify verify;
        readonly Sign sign;
        readonly GCHandle context;
        public readonly Callbacks callbacks;
        public Identity() {
            var publicKey = key.ExportRSAPublicKey();
            var before = Encoding.ASCII.GetBytes(DateTime.UtcNow.AddMinutes(-5).ToString("yyyyMMddHHmmss'Z'", CultureInfo.InvariantCulture));
            var after = Encoding.ASCII.GetBytes(DateTime.UtcNow.AddYears(5).ToString("yyyyMMddHHmmss'Z'", CultureInfo.InvariantCulture));
            var output = new byte[2048];
            var count = (int)mc_build_tbs(publicKey, (nuint)publicKey.Length, RandomNumberGenerator.GetBytes(16), before, after, output, 2048);
            Check(count > 0, "Rust TBS encoder failed");
            var tbs = output.Take(count).ToArray();
            var signature = key.SignData(tbs, HashAlgorithmName.SHA384, RSASignaturePadding.Pkcs1);
            count = (int)mc_finish_certificate(tbs, (nuint)tbs.Length, signature, (nuint)signature.Length, output, 2048);
            Check(count > 0, "Rust certificate encoder failed");
            certificate = output.Take(count).ToArray();
            using (var parsed = X509CertificateLoader.LoadCertificate(certificate))
            using (var publicRSA = parsed.GetRSAPublicKey())
                Check(publicRSA != null && publicRSA.ExportRSAPublicKey().SequenceEqual(publicKey), "Encoded certificate changed the public key");
            context = GCHandle.Alloc(this);
            verify = VerifyServer; sign = SignAgent;
            callbacks = new Callbacks { context = GCHandle.ToIntPtr(context), verify = Marshal.GetFunctionPointerForDelegate(verify), sign = Marshal.GetFunctionPointerForDelegate(sign) };
        }
        static int VerifyServer(IntPtr context, IntPtr pin, IntPtr der, nuint derLen, IntPtr signature, nuint sigLen, IntPtr transcript) {
            try {
                var self = (Identity)GCHandle.FromIntPtr(context).Target;
                self.verifications++;
                using var cert = X509CertificateLoader.LoadCertificate(Read(der, checked((int)derLen)));
                using var key = cert.GetRSAPublicKey();
                if (key == null || (key.KeySize != 2048 && key.KeySize != 3072)) return 1;
                if (!CryptographicOperations.FixedTimeEquals(SHA384.HashData(key.ExportRSAPublicKey()), Read(pin, 48))) return 2;
                return key.VerifyData(Read(transcript, 144), Read(signature, checked((int)sigLen)), HashAlgorithmName.SHA384, RSASignaturePadding.Pkcs1) ? 0 : 3;
            } catch { return 1; } // No exception crosses the C ABI.
        }
        static int SignAgent(IntPtr context, IntPtr transcript, IntPtr output) {
            try {
                var self = (Identity)GCHandle.FromIntPtr(context).Target;
                self.signatures++;
                var signature = self.key.SignData(Read(transcript, 144), HashAlgorithmName.SHA384, RSASignaturePadding.Pkcs1);
                if (self.corruptSignature) signature[0] ^= 1;
                Marshal.Copy(signature, 0, output, signature.Length);
                return signature.Length;
            } catch { return -1; }
        }
        public void Dispose() { context.Free(); key.Dispose(); GC.KeepAlive(verify); GC.KeepAlive(sign); }
    }

    sealed class Outcome { public bool authenticated; public int signs; public int verifies; public string failure = ""; }

    static async Task<Outcome> Connect(int port, string mode, Identity identity, X509Certificate2 root, byte[] pin, bool trustRoot = true, string host = "localhost") {
        var result = new Outcome();
        identity.signatures = 0; identity.verifications = 0;
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(4));
        using var socket = new ClientWebSocket();
        byte[] tlsHash = null;
        socket.Options.RemoteCertificateValidationCallback = (_sender, certificate, _chain, errors) => {
            if (certificate == null || (errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0) return false;
            using var leaf = X509CertificateLoader.LoadCertificate(certificate.GetRawCertData());
            using var chain = new X509Chain();
            chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck; // Ephemeral, isolated test CA has no CRL.
            chain.ChainPolicy.ApplicationPolicy.Add(new Oid("1.3.6.1.5.5.7.3.1"));
            if (trustRoot) chain.ChainPolicy.CustomTrustStore.Add(root);
            if (!chain.Build(leaf)) return false;
            tlsHash = SHA384.HashData(leaf.RawData);
            return true;
        };
        IntPtr handle = IntPtr.Zero;
        try {
            await socket.ConnectAsync(new Uri($"wss://{host}:{port}/{mode}/agent.ashx"), cancellation.Token);
            Check(tlsHash != null, "TLS was not authenticated");
            handle = mc_new(tlsHash, pin, RandomNumberGenerator.GetBytes(48), identity.certificate, (nuint)identity.certificate.Length, identity.callbacks);
            Check(handle != IntPtr.Zero, "Bridge initialization failed");
            Check(mc_share_new(handle, 8) == IntPtr.Zero, "Consent gate existed before server authentication");
            var hello = new byte[98];
            Check(mc_hello(handle, hello, 98) == 98, "Client hello failed");
            await socket.SendAsync(new ArraySegment<byte>(hello), WebSocketMessageType.Binary, true, cancellation.Token);
            while (!result.authenticated) {
                var buffer = new byte[8581];
                int count = 0;
                WebSocketReceiveResult message;
                do {
                    message = await socket.ReceiveAsync(new ArraySegment<byte>(buffer, count, buffer.Length - count), cancellation.Token);
                    Check(message.MessageType == WebSocketMessageType.Binary, "Non-binary handshake frame");
                    count += message.Count;
                    Check(count <= 8580, "Message exceeds handshake limit");
                } while (!message.EndOfMessage);
                int progress = mc_receive(handle, buffer, (nuint)count);
                Check(progress > 0, "Rust rejected the authentication message");
                if (progress == 2) {
                    var name = Encoding.UTF8.GetBytes("iPhone de Chloé");
                    var pinned = GCHandle.Alloc(name, GCHandleType.Pinned);
                    try {
                        var registration = new Registration { architecture = 0xfffffff0, version = 1, platform = 1,
                            mesh = Enumerable.Repeat((byte)0x77, 48).ToArray(), name = pinned.AddrOfPinnedObject(), nameLen = (nuint)name.Length };
                        var proof = new byte[8580]; var info = new byte[327];
                        Check(mc_register(handle, ref registration, proof, 8580, info, 327, out var lengths) == 0, "Registration failed");
                        await socket.SendAsync(new ArraySegment<byte>(proof, 0, (int)lengths.identity), WebSocketMessageType.Binary, true, cancellation.Token);
                        await socket.SendAsync(new ArraySegment<byte>(info, 0, (int)lengths.info), WebSocketMessageType.Binary, true, cancellation.Token);
                    } finally { pinned.Free(); }
                } else if (progress == 3) result.authenticated = true;
            }
            Check(mc_share_new(handle, 0) == IntPtr.Zero, "Missing desktop rights accepted");
            Check(mc_share_new(handle, 0x10008) == IntPtr.Zero, "No-desktop restriction ignored");
            IntPtr share = mc_share_new(handle, 256);
            Check(share != IntPtr.Zero, "View-only authorized operator rejected");
            try {
                Check(mc_share_event(share, 3) == 0, "Media allowed without consent");
                Check(mc_share_event(share, 2) < 0, "Capture bypassed local consent");
                Check(mc_share_new(handle, 8) == IntPtr.Zero, "Second concurrent viewer admitted");
                Check(mc_share_event(share, 1) == 0, "Local approval failed");
                Check(mc_share_event(share, 3) == 0, "Media allowed before capture confirmation");
                Check(mc_share_event(share, 4) < 0 && mc_share_event(share, 5) < 0, "Privacy changed before capture");
                Check(mc_share_event(share, 2) == 0 && mc_share_event(share, 3) == 1, "Authorized media denied");
                Check(mc_share_event(share, 4) == 0 && mc_share_event(share, 3) == 0, "Hidden screen still allowed live video");
                Check(mc_share_event(share, 6) == 1, "Hiding video revoked chat and the session");
                Check(mc_share_event(share, 5) == 0 && mc_share_event(share, 3) == 1, "Local resume did not allow live video");
                Check(mc_share_event(share, 1) < 0, "Duplicate consent accepted");
            } finally { mc_share_free(share); }
            share = mc_share_new(handle, 8);
            Check(share != IntPtr.Zero, "New request after stop rejected");
            try {
                Check(mc_share_event(share, 3) == 0, "Consent leaked into next session");
                Check(mc_share_event(share, 1) == 0 && mc_share_event(share, 2) == 0, "Second consent failed");
                mc_free(handle); handle = IntPtr.Zero;
                Check(mc_share_event(share, 3) == 0, "Disconnect did not revoke live share");
                Check(mc_share_event(share, 6) == 0 && mc_share_event(share, 5) < 0, "Disconnected share kept assistance or resumed video");
                Check(mc_share_event(share, 1) < 0, "Disconnected share restarted");
            } finally { mc_share_free(share); }
        } catch (Exception error) { result.authenticated = false; result.failure = error.GetType().Name + ": " + error.Message; }
        finally {
            socket.Abort();
            if (handle != IntPtr.Zero) mc_free(handle);
            result.signs = identity.signatures; result.verifies = identity.verifications;
        }
        return result;
    }

    public static void Run(string directory) {
        string library = Path.Combine(directory, "target", "debug", "meshcentral_ios_bridge.dll");
        NativeLibrary.SetDllImportResolver(typeof(NativeInteropTests).Assembly, (name, _assembly, _search) =>
            name == "meshcentral_ios_bridge" ? NativeLibrary.Load(library) : IntPtr.Zero);
        var quality = mc_quality_new();
        Check(quality != IntPtr.Zero, "Quality allocation failed");
        try {
            Check(mc_quality_observe(quality, 2000, 8192) == 0, "Slow link did not degrade");
            for (int i = 0; i < 11; i++) Check(mc_quality_observe(quality, 50, 8192) == 0, "Premature recovery");
            Check(mc_quality_observe(quality, 50, 8192) == 1, "Stable link did not recover");
            Check(mc_transfer_next(9000, 8192, 808) == 9000, "Transfer boundary failed");
            Check(mc_transfer_next(9000, 8192, 809) == -1, "Transfer overflow accepted");
        } finally { mc_quality_free(quality); }
        Console.WriteLine("PASS: adaptive quality and document bounds through the actual Rust C ABI.");
        var transfer = mc_transfer_new(10);
        Check(transfer != IntPtr.Zero, "Document allocation failed");
        try {
            Check(mc_transfer_chunk(transfer, 0, 5) == -1, "Document accepted without local consent");
            Check(mc_transfer_approve(transfer) == 0, "Document approval failed");
            Check(mc_transfer_chunk(transfer, 1, 5) == -1, "Document gap accepted");
            Check(mc_transfer_chunk(transfer, 0, 5) == 5, "First document chunk failed");
            Check(mc_transfer_chunk(transfer, 0, 5) == -1, "Duplicate document chunk accepted");
            Check(mc_transfer_chunk(transfer, 5, 5) == 10, "Final document chunk failed");
            Check(mc_transfer_chunk(transfer, 10, 1) == -1, "Completed document extended");
        } finally { mc_transfer_free(transfer); }
        Console.WriteLine("PASS: per-document Rust consent and exact sequence through C ABI.");
        using var identity = new Identity();
        using var caKey = RSA.Create(2048);
        var caRequest = new CertificateRequest("CN=Ephemeral MeshCentral Test CA", caKey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        caRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        caRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign, true));
        using var ca = caRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(1));
        using var tlsKey = RSA.Create(2048);
        var tlsRequest = new CertificateRequest("CN=localhost", tlsKey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        var san = new SubjectAlternativeNameBuilder(); san.AddDnsName("localhost");
        tlsRequest.CertificateExtensions.Add(san.Build());
        tlsRequest.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new Oid("1.3.6.1.5.5.7.3.1") }, false));
        using var tlsCertificate = tlsRequest.Create(ca, DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddHours(1), RandomNumberGenerator.GetBytes(16));
        using var serverKey = RSA.Create(3072);
        var serverRequest = new CertificateRequest("CN=MeshCentral agent identity", serverKey, HashAlgorithmName.SHA384, RSASignaturePadding.Pkcs1);
        using var serverCertificate = serverRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(1));
        var pin = SHA384.HashData(serverKey.ExportRSAPublicKey());

        var start = new ProcessStartInfo("node") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = directory };
        start.ArgumentList.Add(Path.Combine(directory, "tools", "tls-fixture.cjs"));
        using var process = Process.Start(start);
        var diagnostics = new StringBuilder();
        process.ErrorDataReceived += (_sender, e) => { if (e.Data != null) lock (diagnostics) diagnostics.AppendLine(e.Data); };
        process.BeginErrorReadLine();
        try {
            process.StandardInput.WriteLine(JsonSerializer.Serialize(new {
                tlsKey = tlsKey.ExportPkcs8PrivateKeyPem(), tlsCertificate = tlsCertificate.ExportCertificatePem(),
                agentKey = serverKey.ExportPkcs8PrivateKeyPem(), agentCertificate = Convert.ToBase64String(serverCertificate.RawData),
                meshID = Convert.ToHexString(Enumerable.Repeat((byte)0x77, 48).ToArray()), deviceID = NodeID(identity.key)
            }));
            process.StandardInput.Flush();
            var ready = process.StandardOutput.ReadLineAsync();
            Check(ready.Wait(TimeSpan.FromSeconds(10)) && int.TryParse(ready.Result, out _), "Fixture did not start: " + diagnostics);
            int port = int.Parse(ready.Result, CultureInfo.InvariantCulture);

            var valid = Connect(port, "valid", identity, ca, pin).GetAwaiter().GetResult();
            Check(valid.authenticated && valid.signs == 1 && valid.verifies == 1, "Valid TLS/native RSA authentication failed: " + valid.failure + " " + diagnostics);
            Console.WriteLine("PASS: real WSS + certificate pin + RSA/SHA-384 + upstream registration ACK through Rust C ABI.");
            var again = Connect(port, "valid", identity, ca, pin).GetAwaiter().GetResult();
            Check(again.authenticated, "Reconnect with stable device identity failed");
            Console.WriteLine("PASS: fresh-nonce reconnect with stable device identity.");
            Console.WriteLine("PASS: C ABI consent/capture gates, view-only rights, one viewer, fresh consent and disconnect revocation.");

            var wrongPin = (byte[])pin.Clone(); wrongPin[0] ^= 1;
            var rejectedPin = Connect(port, "valid", identity, ca, wrongPin).GetAwaiter().GetResult();
            Check(!rejectedPin.authenticated && rejectedPin.signs == 0 && rejectedPin.verifies == 1, "Wrong server pin was not rejected before signing");
            Console.WriteLine("PASS: incorrect server identity pin rejected before agent signing.");
            foreach (string mode in new[] { "bad-signature", "bad-binding", "oversized", "early-ack", "silent" }) {
                var rejected = Connect(port, mode, identity, ca, pin).GetAwaiter().GetResult();
                Check(!rejected.authenticated && rejected.signs == 0, mode + " did not fail closed");
                string expected = mode == "oversized" ? "Message exceeds handshake limit" : mode == "silent" ? "canceled" : "Rust rejected";
                Check(rejected.failure.Contains(expected, StringComparison.OrdinalIgnoreCase), mode + " failed for an unrelated reason: " + rejected.failure);
                Check(rejected.verifies == (mode == "bad-signature" ? 1 : 0), mode + " invoked crypto at the wrong stage");
                Console.WriteLine("PASS: " + mode + " rejected without disclosing agent identity proof.");
            }
            foreach (bool wrongHost in new[] { false, true }) {
                var rejected = Connect(port, "valid", identity, ca, pin, wrongHost, wrongHost ? "127.0.0.1" : "localhost").GetAwaiter().GetResult();
                Check(!rejected.authenticated && rejected.verifies == 0 && rejected.signs == 0, "Invalid TLS peer was accepted");
                Console.WriteLine("PASS: " + (wrongHost ? "TLS hostname mismatch" : "untrusted TLS CA") + " rejected before MeshCentral authentication.");
            }
            identity.corruptSignature = true;
            var badAgent = Connect(port, "valid", identity, ca, pin).GetAwaiter().GetResult();
            Check(!badAgent.authenticated && badAgent.signs == 1, "Upstream accepted an invalid agent signature");
            Console.WriteLine("PASS: actual MeshCentral server rejects corrupted agent signature.");
            Console.WriteLine("11 live connection cases passed; no private keys or certificates persisted.");
        } finally {
            if (!process.HasExited) process.Kill(true);
            process.WaitForExit();
        }
    }
}
