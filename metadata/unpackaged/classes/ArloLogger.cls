/**
 * ArloLogger
 * 
 * Configurable logging utility for Arlo integration classes.
 * Provides centralized logging with configurable log levels.
 * 
 * @author System Generated
 * @version 1.0
 */
public with sharing class ArloLogger {
    
    // Log levels
    public enum LogLevel {
        NONE,      // No logging
        ERROR,     // Errors only
        WARN,      // Warnings and errors
        INFO,      // Info, warnings, and errors
        DEBUG,     // All logging (default)
        TRACE      // Verbose tracing (includes sensitive data - use with caution)
    }
    
    // Current log level (default to DEBUG for backward compatibility)
    private static LogLevel currentLevel = LogLevel.DEBUG;
    
    // Custom Setting to control log level
    private static final String LOG_LEVEL_SETTING = 'Arlo_Log_Level__c';
    
    /**
     * Initialize log level from Custom Setting or use default
     */
    static {
        try {
            // Try to get log level from Custom Setting (if it exists)
            // For now, default to DEBUG to maintain backward compatibility
            currentLevel = LogLevel.DEBUG;
        } catch (Exception e) {
            // If Custom Setting doesn't exist, use default
            currentLevel = LogLevel.DEBUG;
        }
    }
    
    /**
     * Set log level programmatically
     * 
     * @param level LogLevel enum value
     */
    public static void setLogLevel(LogLevel level) {
        if (level != null) {
            currentLevel = level;
        }
    }
    
    /**
     * Get current log level
     * 
     * @return Current LogLevel
     */
    public static LogLevel getLogLevel() {
        return currentLevel;
    }
    
    /**
     * Log debug message
     * 
     * @param message Message to log
     */
    public static void debug(String message) {
        if (shouldLog(LogLevel.DEBUG)) {
            System.debug(LoggingLevel.DEBUG, formatMessage('DEBUG', message));
        }
    }
    
    /**
     * Log debug message with class context
     * 
     * @param className Class name for context
     * @param message Message to log
     */
    public static void debug(String className, String message) {
        if (shouldLog(LogLevel.DEBUG)) {
            System.debug(LoggingLevel.DEBUG, formatMessage(className, 'DEBUG', message));
        }
    }
    
    /**
     * Log info message
     * 
     * @param message Message to log
     */
    public static void info(String message) {
        if (shouldLog(LogLevel.INFO)) {
            System.debug(LoggingLevel.INFO, formatMessage('INFO', message));
        }
    }
    
    /**
     * Log info message with class context
     * 
     * @param className Class name for context
     * @param message Message to log
     */
    public static void info(String className, String message) {
        if (shouldLog(LogLevel.INFO)) {
            System.debug(LoggingLevel.INFO, formatMessage(className, 'INFO', message));
        }
    }
    
    /**
     * Log warning message
     * 
     * @param message Message to log
     */
    public static void warn(String message) {
        if (shouldLog(LogLevel.WARN)) {
            System.debug(LoggingLevel.WARN, formatMessage('WARN', message));
        }
    }
    
    /**
     * Log warning message with class context
     * 
     * @param className Class name for context
     * @param message Message to log
     */
    public static void warn(String className, String message) {
        if (shouldLog(LogLevel.WARN)) {
            System.debug(LoggingLevel.WARN, formatMessage(className, 'WARN', message));
        }
    }
    
    /**
     * Log error message
     * 
     * @param message Message to log
     */
    public static void error(String message) {
        if (shouldLog(LogLevel.ERROR)) {
            System.debug(LoggingLevel.ERROR, formatMessage('ERROR', message));
        }
    }
    
    /**
     * Log error message with class context
     * 
     * @param className Class name for context
     * @param message Message to log
     */
    public static void error(String className, String message) {
        if (shouldLog(LogLevel.ERROR)) {
            System.debug(LoggingLevel.ERROR, formatMessage(className, 'ERROR', message));
        }
    }
    
    /**
     * Log error with exception
     * 
     * @param message Message to log
     * @param ex Exception to log
     */
    public static void error(String message, Exception ex) {
        if (shouldLog(LogLevel.ERROR)) {
            System.debug(LoggingLevel.ERROR, formatMessage('ERROR', message));
            if (ex != null) {
                System.debug(LoggingLevel.ERROR, 'Exception: ' + ex.getMessage());
                System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + ex.getStackTraceString());
            }
        }
    }
    
    /**
     * Log error with exception and class context
     * 
     * @param className Class name for context
     * @param message Message to log
     * @param ex Exception to log
     */
    public static void error(String className, String message, Exception ex) {
        if (shouldLog(LogLevel.ERROR)) {
            System.debug(LoggingLevel.ERROR, formatMessage(className, 'ERROR', message));
            if (ex != null) {
                System.debug(LoggingLevel.ERROR, className + ': Exception: ' + ex.getMessage());
                System.debug(LoggingLevel.ERROR, className + ': Stack Trace: ' + ex.getStackTraceString());
            }
        }
    }
    
    /**
     * Log trace message (includes potentially sensitive data - use with caution)
     * 
     * @param message Message to log
     */
    public static void trace(String message) {
        if (shouldLog(LogLevel.TRACE)) {
            System.debug(LoggingLevel.FINE, formatMessage('TRACE', message));
        }
    }
    
    /**
     * Log trace message with class context
     * 
     * @param className Class name for context
     * @param message Message to log
     */
    public static void trace(String className, String message) {
        if (shouldLog(LogLevel.TRACE)) {
            System.debug(LoggingLevel.FINE, formatMessage(className, 'TRACE', message));
        }
    }
    
    /**
     * Check if message should be logged based on current log level
     * 
     * @param messageLevel Log level of the message
     * @return true if message should be logged
     */
    private static Boolean shouldLog(LogLevel messageLevel) {
        if (currentLevel == LogLevel.NONE) {
            return false;
        }
        
        // Map log levels to priority (higher number = more verbose)
        Map<LogLevel, Integer> levelPriority = new Map<LogLevel, Integer>{
            LogLevel.NONE => 0,
            LogLevel.ERROR => 1,
            LogLevel.WARN => 2,
            LogLevel.INFO => 3,
            LogLevel.DEBUG => 4,
            LogLevel.TRACE => 5
        };
        
        Integer currentPriority = levelPriority.get(currentLevel);
        Integer messagePriority = levelPriority.get(messageLevel);
        
        return messagePriority <= currentPriority;
    }
    
    /**
     * Format log message with timestamp and level
     * 
     * @param level Log level string
     * @param message Message to format
     * @return Formatted message
     */
    private static String formatMessage(String level, String message) {
        return '[' + level + '] ' + message;
    }
    
    /**
     * Format log message with class name, timestamp and level
     * 
     * @param className Class name
     * @param level Log level string
     * @param message Message to format
     * @return Formatted message
     */
    private static String formatMessage(String className, String level, String message) {
        return '[' + className + '][' + level + '] ' + message;
    }
    
    /**
     * Sanitize sensitive data from log messages
     * Replaces passwords and auth headers with [REDACTED]
     * 
     * @param message Original message
     * @return Sanitized message
     */
    public static String sanitize(String message) {
        if (String.isBlank(message)) {
            return message;
        }
        
        // Redact Basic Auth headers
        String sanitized = message.replaceAll('Basic [A-Za-z0-9+/=]+', 'Basic [REDACTED]');
        
        // Redact password patterns (if any)
        sanitized = sanitized.replaceAll('(?i)password["\']?\\s*[:=]\\s*["\']?[^"\'\\s]+', 'password: [REDACTED]');
        
        return sanitized;
    }
}
