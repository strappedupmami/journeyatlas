namespace AtlasMasaWindows.Services;

public sealed class SystemPerformanceProfile
{
    public int CpuCores { get; init; }
    public long PhysicalMemoryGb { get; init; }
    public int MaxQueueWorkers { get; init; }
    public bool HighPerformanceMode { get; init; }
    public bool UltraPerformanceMode { get; init; }
    public string Label { get; init; } = "balanced";

    public static SystemPerformanceProfile Detect()
    {
        var cores = Math.Max(1, Environment.ProcessorCount);
        long memoryGb = 8;
        try
        {
            var bytes = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
            if (bytes > 0)
            {
                memoryGb = Math.Max(4, bytes / (1024L * 1024L * 1024L));
            }
        }
        catch
        {
            // keep default
        }

        var ultraPerf = cores >= 16 && memoryGb >= 32;
        var highPerf = ultraPerf || (cores >= 8 && memoryGb >= 16);
        var workers = ultraPerf
            ? Math.Min(12, Math.Max(4, (int)Math.Ceiling(cores / 2.0)))
            : highPerf
                ? Math.Min(8, Math.Max(3, (int)Math.Ceiling(cores / 2.0)))
                : Math.Max(1, Math.Min(4, Math.Max(2, cores / 3)));

        return new SystemPerformanceProfile
        {
            CpuCores = cores,
            PhysicalMemoryGb = memoryGb,
            MaxQueueWorkers = workers,
            HighPerformanceMode = highPerf,
            UltraPerformanceMode = ultraPerf,
            Label = ultraPerf ? "ultra_performance" : highPerf ? "high_performance" : "balanced"
        };
    }
}
