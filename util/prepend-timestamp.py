from datetime import datetime
from sys import stdin

chars = []
prev = ""
while True:
    char = stdin.read(1)
    if char != "\x00":
        chars.append(char)
    if char == "":
        chars.append("\n")

    if char in {"", "\x00", "\n"}:
        timestamp = datetime.now().isoformat(timespec="microseconds")
        line = "".join(chars)

        if prev != "\x00":
            print(f"[{timestamp}] ", end="", flush=True)
        print(line, end="", flush=True)

        chars = []
        prev = char

    if char == "":
        break
