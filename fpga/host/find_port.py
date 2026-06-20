"""
find_port.py — List all serial ports on this machine.

Run this to find the correct COM port before using send_image.py.
Look for a port named "CP210x", "USB Serial", or "USB-UART".
"""

try:
    import serial.tools.list_ports as lp
except ImportError:
    print("Run: pip install pyserial")
    raise

ports = sorted(lp.comports())
if not ports:
    print("No serial ports found.")
else:
    print(f"{'Port':<12} {'Description'}")
    print("-" * 50)
    for port, desc, hwid in ports:
        print(f"{port:<12} {desc}")
