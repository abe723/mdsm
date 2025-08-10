# mdsm v1.011

## Overview

**mdsm** (Multi-Threaded Backup Scheduler) is a robust backup scheduling tool utilizing IBM Storage Protect. The current version, **v1.011**, features a complete rewrite of many functions to enhance performance and reliability.

## Key Features of v1.011

| Feature                             | Description                                                                                               |
|-------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Added Functionality                 | Added getfsweight.sh script which will scan filesystems and assign them a weight, useful for fine tuning mode selection. |
| Enhanced Logging                    | Introduced a new `logerror` function and improved the existing `die` function for better error handling and reporting. |
| Refined Trap Logic                  | Streamlined trap logic to ensure more reliable cleanup and exit conditions, resulting in accurate return code generation. |
| Inline IFS Configuration             | Improved the configuration parser to utilize inline IFS checks, enhancing flexibility and robustness.      |
| Max Process Validation               | Implemented checks to ensure the `maxproc` variable is set and its value exceeds zero, preventing misconfigurations. |
| Code Optimization                    | Removed redundant code within the sanity check routine to enhance performance and maintainability.        |
| Read-Only LOG Variable               | Changed the `LOG` variable to be read-only, reinforcing intended usage and preventing unintended modifications. |
| Safer LARGEFS Checks                | Enhanced checks for the `LARGEFS` variable to ensure it contains at least one element, improving reliability in large filesystem operations. |
| Improved Condition Code Logic        | Revised condition code logic within the `ba` function for more accurate status reporting.                |
| Redundancy Elimination               | Streamlined the `checkErr` function by removing redundant checks, resulting in cleaner code.            |
| Detailed Cleanup Reporting           | The `logCleanup` function now provides a count of items being removed during cleanup, enhancing transparency. |
| Comprehensive Summary Table          | The summary table now includes a "Backup Complete" message, with status counts moved to the end of the job for better readability. |
| Simplified High-Performance Mode     | Streamlined the implementation of high-performance mode, using `df` to generate filesystem arrays with `awk`, reducing complexity. |
| Enhanced Job Wait Routine            | Improved the routine for waiting on jobs to complete, ensuring more reliable execution.                   |
| Efficient RCFILE Reading             | Streamlined reading of the `RCFILE` variable, eliminating the need to invoke `cat`, thereby improving performance. |

## Change Log

| Version | Date          | Changes                                                                                     |
|---------|---------------|---------------------------------------------------------------------------------------------|
| 1.011   | Oct 18, 2024  | **Revised**: Comprehensive rework of multiple functions to enhance performance and reliability. |
| 1.010   | Jul 26, 2024  | **Enhanced**: Improved the logging function for better clarity and usability.                |
| 1.009   | Jun 05, 2024  | **Refined**: Cleared STDERR output from internal commands, addressing issues with invalid configuration filenames. |
| 1.008   | Jun 04, 2024  | **Introduced**: Timeout functionality with appropriate handling of return codes.             |
| 1.007   | Jun 03, 2024  | **Removed**: Instance counting feature to streamline processing due to forking behavior.     |
| 1.006   | May 29, 2024  | **Implemented**: Added a trap function for graceful cleanup on exit or failure.             |
| 1.005   | May 25, 2024  | **Rebranded**: Underwent significant bug fixes and enhancements to documentation clarity.    |
| 1.004   | May 24, 2024  | **Enhanced**: Enabled simultaneous execution of multiple instances without interference. Added support for prioritization and large filesystem (LARGEFS) mode. Revised invocation to require a configuration file, with modifications to sourcing methods. |
| 1.003   | May 19, 2024  | **Optimized**: Established error and completion checks after each PID wait iteration, replacing the previous after-loop checks. Updated `$LOG` to display the absolute path; `mdsm.ini` can now override custom settings. |
| 1.002   | May 17, 2024  | **Fixed**: Resolved issues within the cleanup function and incorporated versioning features. |
| 1.001   | May 16, 2024  | **Enhanced**: Conducted condition code checks after each job execution and included timestamps in the log directory for better tracking. |

## Getting Started

To begin using **mdsm**, follow these steps:

1. **Installation**: Ensure that you have Bash version 4.4 or higher and IBM Storage Protect installed.
2. **Configuration**: Create a configuration file (`mdsm.ini`) with your desired settings. Refer to the sample configuration file included in the repository for guidance.
3. **Running the Script**:
   - Invoke the script using the following command:
     ```bash
     ./mdsm.sh mdsm.ini
     ```
   - Monitor the log output for progress and status updates.
4. **Troubleshooting**: If you encounter any issues, check the log file for detailed error messages. You can also consult the GitHub repository for FAQs and community support.

## Additional Resources

- **Documentation**: Comprehensive documentation is available in the `/docs` directory of the repository.
- **Support**: For further assistance, please reach out to the author or create an issue in the GitHub repository.
- **Contribution**: Contributions to improve the script are welcome! Please follow the contribution guidelines outlined in the repository.

## Author

**Allan Bednarowski**  
**https://git.bednarowski.ca**
