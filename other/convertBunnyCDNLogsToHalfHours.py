import os
import time
import argparse

def get_half_hour_from_timestamp(timestamp):
    ts_seconds = int(timestamp) / 1000
    time_struct = time.gmtime(ts_seconds)
    hour = time_struct.tm_hour
    minute = time_struct.tm_min
    half_hour = 0 if minute < 30 else 30
    return f"{hour:02d}_{half_hour:02d}"

def process_log_file(input_file, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    file_handles = {}

    try:
        with open(input_file, 'r') as file:
            for line in file:
                parts = line.split('|', 3)  # Split only the first 3 times
                if len(parts) > 3:
                    timestamp = parts[2]
                    half_hour = get_half_hour_from_timestamp(timestamp)

                    if half_hour not in file_handles:
                        file_handles[half_hour] = open(os.path.join(output_dir, f"{half_hour}.log"), 'a')

                    file_handles[half_hour].write(line)

    finally:
        # Ensure all file handles are closed properly
        for handle in file_handles.values():
            handle.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process a log file and separate logs into half-hourly files.')
    parser.add_argument('input_file', help='The input log file')
    parser.add_argument('output_dir', help='The directory to store the separated log files')

    args = parser.parse_args()

    process_log_file(args.input_file, args.output_dir)
    print("Logs have been separated into half-hourly files.")
