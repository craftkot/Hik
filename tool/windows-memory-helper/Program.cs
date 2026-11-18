using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Buffers.Binary;

namespace EhtidMemoryHelper;

internal sealed class Request
{
    public string Command { get; set; } = "";
    public int Pid { get; set; }
    public string Format { get; set; } = "i32";
    public string Value { get; set; } = "";
    public string Expected { get; set; } = "";
    public string Replacement { get; set; } = "";
    public string Address { get; set; } = "";
    public string[] Addresses { get; set; } = Array.Empty<string>();
    public string[] Baselines { get; set; } = Array.Empty<string>();
    public string Mode { get; set; } = "changed";
    public long MaxBytes { get; set; } = 536870912; // 512 MiB, explicit bounded scan
    public int MaxResults { get; set; } = 3000;
    public int Alignment { get; set; } = 4;
}

internal static class Program
{
    private const uint QueryRead = 0x0400 | 0x0010; // QUERY_INFORMATION / VM_READ
    private const uint QueryReadWrite = QueryRead | 0x0020 | 0x0008;
    private const uint MemCommit = 0x1000;
    private const long MaxUserAddress = 0x00007FFFFFFF0000L;
    private const int ChunkSize = 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions =
        new() { PropertyNameCaseInsensitive = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static int Main(string[] args)
    {
        try
        {
            if (!OperatingSystem.IsWindows() || !Environment.Is64BitProcess)
                throw new InvalidOperationException("Only Windows x64 is supported");
            if (args.Length == 1 && args[0] == "--selftest")
            {
                Console.Write(JsonSerializer.Serialize(SelfTest(), JsonOptions));
                return 0;
            }
            if (args.Length != 0) throw new ArgumentException("Unknown argument");
            var input = Console.In.ReadToEnd();
            if (input.Length < 2 || input.Length > 1_000_000)
                throw new ArgumentException("Invalid request length");
            var request = JsonSerializer.Deserialize<Request>(input, JsonOptions)
                ?? throw new ArgumentException("Invalid JSON request");
            var response = request.Command.ToLowerInvariant() switch
            {
                "list" => ListWindows(),
                "scan" => Scan(request),
                "refine" => Refine(request),
                "compare" => Compare(request),
                "write" => Write(request),
                _ => throw new ArgumentException("Unknown command")
            };
            Console.Write(JsonSerializer.Serialize(response, JsonOptions));
            return 0;
        }
        catch (Exception error)
        {
            Console.Write(JsonSerializer.Serialize(new { ok = false, error = error.Message }, JsonOptions));
            return 1;
        }
    }

    private static object ListWindows()
    {
        var visible = new List<object>();
        var ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            { "explorer", "dwm", "sihost", "SearchHost", "ShellExperienceHost",
              "RuntimeBroker", "TextInputHost", "ApplicationFrameHost" };
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    if (process.Id == Environment.ProcessId || process.MainWindowHandle == IntPtr.Zero)
                        continue;
                    var name = process.ProcessName;
                    if (ignored.Contains(name) || string.IsNullOrWhiteSpace(process.MainWindowTitle))
                        continue;
                    visible.Add(new { pid = process.Id, name, title = process.MainWindowTitle });
                }
                catch (Exception) { /* Hidden, inaccessible or exiting process. */ }
            }
            if (visible.Count >= 150) break;
        }
        return new { ok = true, processes = visible };
    }

    private static object Scan(Request request)
    {
        EnsurePid(request.Pid);
        var needle = Encode(request.Format, request.Value);
        var maxBytes = request.MaxBytes;
        if (maxBytes < 16 * 1024 * 1024 || maxBytes > 2L * 1024 * 1024 * 1024)
            throw new ArgumentException("Scan budget must be 16 MiB to 2048 MiB");
        if (request.MaxResults < 1 || request.MaxResults > 5000)
            throw new ArgumentException("Result limit must be 1..5000");
        var alignment = request.Alignment;
        if (alignment != 1 && alignment != 4 && alignment != 8)
            throw new ArgumentException("Alignment must be 1, 4 or 8");
        var hits = new List<string>();
        long processedBytes = 0;
        long regionCount = 0;
        long cursor = 0x10000;
        bool capped = false;
        using var process = Process.GetProcessById(request.Pid);
        if (process.HasExited) throw new InvalidOperationException("Game process exited");
        var handle = OpenProcess(QueryRead, false, (uint)request.Pid);
        if (handle == IntPtr.Zero) throw new InvalidOperationException(
            "Cannot read this process. Select your offline game; no elevation or protection bypass is attempted");
        try
        {
            while (cursor < MaxUserAddress)
            {
                var size = (nuint)Marshal.SizeOf<MemoryInfo>();
                if (VirtualQueryEx(handle, (nint)cursor, out var region, size) == 0) break;
                var baseAddress = (long)region.BaseAddress;
                var byteCount = (long)region.RegionSize;
                if (byteCount <= 0 || baseAddress >= MaxUserAddress - byteCount)
                    break;
                var end = baseAddress + byteCount;
                cursor = end <= cursor ? cursor + 0x1000 : end;
                if (region.State != MemCommit || !Readable(region.Protect) || byteCount < needle.Length)
                    continue;
                regionCount++;
                long position = Math.Max(baseAddress, 0x10000L);
                while (position < end)
                {
                    if (processedBytes >= maxBytes || hits.Count >= request.MaxResults)
                    {
                        capped = true;
                        break;
                    }
                    int primary = (int)Math.Min(ChunkSize,
                        Math.Min(end - position, maxBytes - processedBytes));
                    if (primary < needle.Length)
                    {
                        processedBytes += primary;
                        break;
                    }
                    int length = (int)Math.Min(primary + needle.Length - 1, end - position);
                    var buffer = new byte[length];
                    bool success = ReadProcessMemory(handle, (nint)position, buffer,
                        (nuint)length, out var read) && (long)read >= needle.Length;
                    processedBytes += primary;
                    if (success)
                    {
                        // Both aligned and deep scans share exactly the
                        // same cross-chunk boundary and candidate limits.
                        if (AddMatches(buffer, needle, position, alignment,
                            primary, (int)read, hits, request.MaxResults))
                            capped = true;
                    }
                    position += primary;
                }
                if (capped) break;
            }
        }
        finally { CloseHandle(handle); }
        return new {
            ok = true, addresses = hits, scannedBytes = processedBytes,
            regions = regionCount, truncated = capped,
            note = capped ? "Limit reached; refine or use a rarer value to find more" :
                "Exact search finished; these are candidate addresses, not verified HP/mana"
        };
    }

    /// Match candidate numeric bytes while respecting the primary chunk
    /// boundary. Additional overlapping bytes only complete values that
    /// *start* in the current chunk; never report the same hit twice.
    private static bool AddMatches(byte[] buffer, byte[] needle,
        long position, int alignment, int primaryLength, int readableLength,
        List<string> hits, int maxResults)
    {
        if (alignment is not (1 or 4 or 8))
            throw new ArgumentException("Invalid scan alignment");
        int last = Math.Min(primaryLength, readableLength - needle.Length + 1);
        if (last <= 0) return false;
        int offset = (int)((alignment - position % alignment) % alignment);
        for (; offset < last; offset += alignment)
        {
            if (buffer.AsSpan(offset, needle.Length).SequenceEqual(needle))
            {
                hits.Add("0x" + (position + offset).ToString("X", CultureInfo.InvariantCulture));
                if (hits.Count >= maxResults) return true;
            }
        }
        return false;
    }

    private static object Refine(Request request)
    {
        EnsurePid(request.Pid);
        var needle = Encode(request.Format, request.Value);
        if (request.Addresses == null || request.Addresses.Length > 5000)
            throw new ArgumentException("Too many candidate addresses");
        var matches = new List<string>();
        var errors = 0;
        var handle = OpenProcess(QueryRead, false, (uint)request.Pid);
        if (handle == IntPtr.Zero) throw new InvalidOperationException("Game process unavailable");
        try
        {
            foreach (var entry in request.Addresses.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                var address = ParseAddress(entry);
                var read = ReadExact(handle, address, needle.Length);
                if (read == null) { errors++; continue; }
                if (read.AsSpan().SequenceEqual(needle)) matches.Add(entry);
            }
        }
        finally { CloseHandle(handle); }
        return new { ok = true, addresses = matches, invalidated = errors, truncated = false };
    }

    /// Compare only a previously found list of candidates. No second full
    /// RAM scan is needed, and no addresses outside the selected list are read.
    /// Every surviving candidate carries its new numeric baseline so further
    /// comparisons work even when values diverge between addresses.
    private static object Compare(Request request)
    {
        EnsurePid(request.Pid);
        var addresses = request.Addresses
            ?? throw new ArgumentException("Missing candidate list");
        var baselines = request.Baselines
            ?? throw new ArgumentException("Missing numeric baselines");
        if (addresses.Length == 0 || addresses.Length > 5000 ||
            addresses.Length != baselines.Length)
            throw new ArgumentException("Expected 1..5000 addresses with matching baseline values");
        if (request.Mode is not ("all" or "changed" or "unchanged" or "increased" or "decreased"))
            throw new ArgumentException("Unsupported comparison mode");
        var width = request.Format is "i32" or "f32" ? 4 :
            request.Format is "i64" or "f64" ? 8 :
            throw new ArgumentException("Unsupported number format");

        var matches = new List<string>();
        var values = new List<string>();
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        int inaccessible = 0;
        var handle = OpenProcess(QueryRead, false, (uint)request.Pid);
        if (handle == IntPtr.Zero)
            throw new InvalidOperationException("Game process is not readable");
        try
        {
            for (int i = 0; i < addresses.Length; i++)
            {
                var item = addresses[i];
                if (!visited.Add(item)) continue;
                var address = ParseAddress(item);
                var currentBytes = ReadExact(handle, address, width);
                if (currentBytes == null) { inaccessible++; continue; }
                if (MatchesComparison(request.Format, baselines[i], currentBytes,
                    request.Mode, out var current))
                {
                    matches.Add(item);
                    values.Add(current);
                }
            }
        }
        finally { CloseHandle(handle); }
        return new {
            ok = true, addresses = matches, values,
            invalidated = inaccessible, truncated = false
        };
    }

    private static bool MatchesComparison(
        string format, string baseline, byte[] bytes,
        string mode, out string current)
    {
        baseline = baseline.Replace(',', '.').Trim();
        var culture = CultureInfo.InvariantCulture;
        int order;
        switch (format)
        {
            case "i32":
                if (!int.TryParse(baseline, NumberStyles.Integer, culture, out var old32))
                    throw new ArgumentException("Invalid Int32 baseline");
                var value32 = BinaryPrimitives.ReadInt32LittleEndian(bytes);
                order = value32.CompareTo(old32);
                current = value32.ToString(culture);
                break;
            case "i64":
                if (!long.TryParse(baseline, NumberStyles.Integer, culture, out var old64))
                    throw new ArgumentException("Invalid Int64 baseline");
                var value64 = BinaryPrimitives.ReadInt64LittleEndian(bytes);
                order = value64.CompareTo(old64);
                current = value64.ToString(culture);
                break;
            case "f32":
                if (!float.TryParse(baseline, NumberStyles.Float, culture, out var oldFloat) ||
                    !float.IsFinite(oldFloat))
                    throw new ArgumentException("Invalid Float32 baseline");
                var valueFloat = BitConverter.Int32BitsToSingle(
                    BinaryPrimitives.ReadInt32LittleEndian(bytes));
                if (!float.IsFinite(valueFloat))
                {
                    current = "";
                    return false;
                }
                order = valueFloat.CompareTo(oldFloat);
                current = valueFloat.ToString("R", culture);
                break;
            case "f64":
                if (!double.TryParse(baseline, NumberStyles.Float, culture, out var oldDouble) ||
                    !double.IsFinite(oldDouble))
                    throw new ArgumentException("Invalid Float64 baseline");
                var valueDouble = BitConverter.Int64BitsToDouble(
                    BinaryPrimitives.ReadInt64LittleEndian(bytes));
                if (!double.IsFinite(valueDouble))
                {
                    current = "";
                    return false;
                }
                order = valueDouble.CompareTo(oldDouble);
                current = valueDouble.ToString("R", culture);
                break;
            default:
                throw new ArgumentException("Unsupported number format");
        }
        return mode switch
        {
            // Read-only snapshot: retain every readable finite candidate,
            // independently of the change against its old baseline.
            "all" => true,
            "changed" => order != 0,
            "unchanged" => order == 0,
            "increased" => order > 0,
            "decreased" => order < 0,
            _ => throw new ArgumentException("Unsupported comparison mode")
        };
    }

    private static object Write(Request request) => WriteInternal(request, allowSelf: false);

    private static object WriteInternal(Request request, bool allowSelf)
    {
        if (allowSelf && request.Pid == Environment.ProcessId) { /* self-test only */ }
        else EnsurePid(request.Pid);
        var expected = Encode(request.Format, request.Expected);
        var replacement = Encode(request.Format, request.Replacement);
        var address = ParseAddress(request.Address);
        if (expected.Length != replacement.Length) throw new ArgumentException("Width mismatch");
        var handle = OpenProcess(QueryReadWrite, false, (uint)request.Pid);
        if (handle == IntPtr.Zero)
            throw new InvalidOperationException("Cannot write: game may be protected, running online, or inaccessible");
        try
        {
            if (VirtualQueryEx(handle, address, out var region,
                    (nuint)Marshal.SizeOf<MemoryInfo>()) == 0 || region.State != MemCommit ||
                !Writable(region.Protect))
                throw new InvalidOperationException("Address no longer points to writable memory");
            var regionStart = (long)region.BaseAddress;
            if ((long)address < regionStart || (long)address - regionStart >
                (long)region.RegionSize - expected.Length)
                throw new InvalidOperationException("Value crosses a memory boundary");
            var before = ReadExact(handle, address, expected.Length)
                ?? throw new InvalidOperationException("Selected address is no longer readable");
            if (!before.AsSpan().SequenceEqual(expected))
                throw new InvalidOperationException("Value changed in the game. Refine and select again");
            if (!WriteProcessMemory(handle, address, replacement, (nuint)replacement.Length,
                    out var written) || (long)written != replacement.Length)
                throw new InvalidOperationException("Windows denied write or game changed memory mapping");
            var actual = ReadExact(handle, address, expected.Length);
            if (actual == null || !actual.AsSpan().SequenceEqual(replacement))
            {
                // Best effort rollback only when the original mapping is still writable.
                WriteProcessMemory(handle, address, before, (nuint)before.Length, out _);
                throw new InvalidOperationException("Verification failed; attempted immediate rollback");
            }
            return new { ok = true, address = request.Address,
                oldValue = request.Expected, newValue = request.Replacement };
        }
        finally { CloseHandle(handle); }
    }

    private static object SelfTest()
    {
        var address = Marshal.AllocHGlobal(64);
        try
        {
            Marshal.WriteInt32(address, 0x10203040);
            var initial = ReadSelf(address, 4);
            if (!initial.AsSpan().SequenceEqual(Encode("i32", "270544960")))
                throw new InvalidOperationException("Initial read/encoding test failed");
            WriteInternal(new Request {
                Pid = Environment.ProcessId, Address = "0x" + address.ToInt64().ToString("X"),
                Format = "i32", Expected = "270544960", Replacement = "7331"
            }, allowSelf: true);
            if (Marshal.ReadInt32(address) != 7331)
                throw new InvalidOperationException("Write/readback selftest failed");
            WriteInternal(new Request {
                Pid = Environment.ProcessId, Address = "0x" + address.ToInt64().ToString("X"),
                Format = "i32", Expected = "7331", Replacement = "270544960"
            }, allowSelf: true);
            if (Marshal.ReadInt32(address) != 0x10203040)
                throw new InvalidOperationException("Restore selftest failed");
            // Pure scan assertions: normal alignment cannot see a packed
            // value at +3, deep scanning can, and a candidate spanning the
            // primary-chunk boundary is reported exactly once.
            var probe = new byte[24];
            var packed = new byte[] { 0x91, 0xA3, 0xB5, 0xC7 };
            packed.AsSpan().CopyTo(probe.AsSpan(3));
            packed.AsSpan().CopyTo(probe.AsSpan(12));
            var normalHits = new List<string>();
            if (AddMatches(probe, packed, 0x10000, 4, 20, 24,
                    normalHits, 5000) ||
                normalHits.Count != 1 || normalHits[0] != "0x1000C")
                throw new InvalidOperationException("Aligned scan matched wrong addresses");
            var deepHits = new List<string>();
            if (AddMatches(probe, packed, 0x10000, 1, 20, 24,
                    deepHits, 5000) ||
                deepHits.Count != 2 ||
                deepHits[0] != "0x10003" || deepHits[1] != "0x1000C")
                throw new InvalidOperationException("Bytewise scan missed packed value");
            var overlap = new byte[12];
            packed.AsSpan().CopyTo(overlap.AsSpan(7));
            var boundaryHits = new List<string>();
            if (AddMatches(overlap, packed, 0x10000, 1, 8, 11,
                    boundaryHits, 5000) ||
                boundaryHits.Count != 1 || boundaryHits[0] != "0x10007")
                throw new InvalidOperationException("Cross-chunk numeric match failed");
            // The start of the next chunk must not appear in this one.
            var nextChunkStart = new byte[12];
            packed.AsSpan().CopyTo(nextChunkStart.AsSpan(8));
            var duplicates = new List<string>();
            if (AddMatches(nextChunkStart, packed, 0x10000, 1, 8, 12,
                    duplicates, 5000) || duplicates.Count != 0)
                throw new InvalidOperationException("Scan repeated next-chunk address");

            if (!MatchesComparison("i32", "250",
                    Encode("i32", "400"), "all", out var snapshot) ||
                snapshot != "400")
                throw new InvalidOperationException("Read-only snapshot failed");
            if (!MatchesComparison("i32", "250",
                    Encode("i32", "250"), "all", out _))
                throw new InvalidOperationException("Unchanged snapshot failed");
            if (!MatchesComparison("i64", "9223372036854775806",
                    Encode("i64", "9223372036854775807"),
                    "increased", out var biggest) ||
                biggest != "9223372036854775807")
                throw new InvalidOperationException("Int64 comparison lost precision");
            if (!MatchesComparison("f32", "12.5",
                    Encode("f32", "10.5"), "decreased", out var f32) ||
                f32 != "10.5")
                throw new InvalidOperationException("Float32 decrease comparison failed");
            if (!MatchesComparison("i32", "7331",
                    Encode("i32", "7331"), "unchanged", out _))
                throw new InvalidOperationException("Unchanged comparison failed");
            if (MatchesComparison("i32", "7331",
                    Encode("i32", "7331"), "changed", out _))
                throw new InvalidOperationException("Changed comparison returned false positive");
            return new { ok = true, selfTest =
                "read, guarded write, readback, restore, relative comparison, bytewise/aligned boundary matching" };
        }
        finally { Marshal.FreeHGlobal(address); }
    }

    private static byte[] ReadSelf(nint address, int width)
    {
        var data = new byte[width];
        Marshal.Copy(address, data, 0, width);
        return data;
    }

    private static byte[]? ReadExact(nint handle, nint address, int width)
    {
        var bytes = new byte[width];
        return ReadProcessMemory(handle, address, bytes, (nuint)width, out var count) &&
            (int)count == width ? bytes : null;
    }

    private static void EnsurePid(int pid)
    {
        if (pid < 1 || pid == 4 || pid == Environment.ProcessId)
            throw new ArgumentException("Select a running, user-owned single-player game process");
    }

    private static nint ParseAddress(string address)
    {
        if (!address.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ||
            !ulong.TryParse(address[2..], NumberStyles.AllowHexSpecifier,
                CultureInfo.InvariantCulture, out var parsed) ||
            parsed < 0x10000 || parsed >= (ulong)MaxUserAddress)
            throw new ArgumentException("Invalid user-space address");
        return unchecked((nint)(long)parsed);
    }

    private static byte[] Encode(string format, string value)
    {
        var bytes = new byte[format switch { "i32" or "f32" => 4, "i64" or "f64" => 8,
            _ => throw new ArgumentException("Unsupported number format") }];
        var normalized = value.Trim().Replace(',', '.');
        var culture = CultureInfo.InvariantCulture;
        switch (format)
        {
            case "i32":
                BinaryPrimitives.WriteInt32LittleEndian(bytes, int.Parse(normalized,
                    NumberStyles.AllowLeadingSign, culture)); break;
            case "i64":
                BinaryPrimitives.WriteInt64LittleEndian(bytes, long.Parse(normalized,
                    NumberStyles.AllowLeadingSign, culture)); break;
            case "f32":
                var f = float.Parse(normalized, NumberStyles.Float, culture);
                if (!float.IsFinite(f)) throw new ArgumentException("Non-finite Float32");
                BinaryPrimitives.WriteInt32LittleEndian(bytes, BitConverter.SingleToInt32Bits(f));
                break;
            case "f64":
                var d = double.Parse(normalized, NumberStyles.Float, culture);
                if (!double.IsFinite(d)) throw new ArgumentException("Non-finite Float64");
                BinaryPrimitives.WriteInt64LittleEndian(bytes, BitConverter.DoubleToInt64Bits(d));
                break;
        }
        return bytes;
    }

    private static bool Readable(uint flags)
    {
        if ((flags & 0x100) != 0 || (flags & 0xFF) == 0x01) return false; // guard / noaccess
        return (flags & 0xFF) is 0x02 or 0x04 or 0x08 or 0x20 or 0x40 or 0x80;
    }
    private static bool Writable(uint flags)
    {
        if ((flags & 0x100) != 0) return false;
        return (flags & 0xFF) is 0x04 or 0x08 or 0x40 or 0x80;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryInfo
    {
        public nint BaseAddress;
        public nint AllocationBase;
        public uint AllocationProtect;
        public uint Alignment1;
        public nuint RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
        public uint Alignment2;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nuint VirtualQueryEx(nint process, nint address,
        out MemoryInfo info, nuint length);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadProcessMemory(nint process, nint address,
        [Out] byte[] buffer, nuint size, out nuint bytesRead);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteProcessMemory(nint process, nint address,
        [In] byte[] buffer, nuint size, out nuint bytesWritten);
}
