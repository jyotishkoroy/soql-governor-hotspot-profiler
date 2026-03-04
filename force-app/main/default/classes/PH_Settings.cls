public with sharing class PH_Settings {
    public static String apiVersion() {
        return '55.0';
    }

    // Client-side ingestion should skip logs above this size (bytes)
    public static Integer maxLogBytes() {
        return 2500000; // 2.5MB default
    }

    public static Integer maxLogsPerRun() {
        return 200;
    }
}
