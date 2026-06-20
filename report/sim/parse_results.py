#!/usr/bin/env python3
"""
parse_results.py — Parse ModelSim assertion log → human-readable HTML report
Usage: python report/sim/parse_results.py [report/sim/sim_log.txt]
Output: report/sim/sim_report.html
"""
import sys
import re
import os
from datetime import datetime

LOG_FILE = sys.argv[1] if len(sys.argv) > 1 else "report/sim/sim_log.txt"
OUT_HTML = os.path.join(os.path.dirname(LOG_FILE), "sim_report.html")

ASSERTION_DESC = {
    "A1":  "No DMEM access during reset",
    "A2":  "PC watchdog — no pipeline deadlock",
    "A3":  "UART TX frame valid (start=0, stop=1)",
    "A4":  "No X/Z in UART TX data",
    "A5":  "Scalar write only to R/G/B region [0x0000–0xBFFF]",
    "A6":  "dmem_sync: no Port A+B same-word write hazard",
    "A7":  "ACK byte = 0xAA",
    "A8":  "All 16384 Y pixels match BT.601 reference",
    "A9":  "No Y pixel > 253 (8-bit overflow check)",
    "A10": "R/G/B DMEM data matches UART-received bytes",
    "A11": "Global timeout guard (8M cycles)",
}

def parse_log(path):
    results = {k: {"status": "NOT_RUN", "details": []} for k in ASSERTION_DESC}
    summary = {"total_pass": 0, "total_fail": 0, "pixels_ok": 0, "pixels_fail": 0,
               "fpga_ready": None, "ack": None, "y_sample": None}

    if not os.path.exists(path):
        return results, summary, []

    raw_lines = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip()
            raw_lines.append(line)

            # Assertion PASS lines
            m = re.search(r'\[PASS\]\[([A-Z0-9]+)\](.+)', line)
            if m:
                aid = m.group(1)
                if aid in results:
                    results[aid]["status"] = "PASS"
                    results[aid]["details"].append(line.strip())

            # Assertion FAIL lines
            m = re.search(r'\[FAIL\]\[([A-Z0-9]+)\](.+)', line)
            if m:
                aid = m.group(1)
                if aid in results:
                    if results[aid]["status"] != "PASS":
                        results[aid]["status"] = "FAIL"
                    results[aid]["details"].append(line.strip())

            # HAZARD (A6)
            if "[HAZARD]" in line:
                results["A6"]["status"] = "FAIL"
                results["A6"]["details"].append(line.strip())
            elif results["A6"]["status"] == "NOT_RUN":
                if "dmem_sync" in line.lower() or "INFO" in line:
                    pass  # no hazard seen yet

            # Summary line
            m = re.search(r'TEST SUMMARY.*PASS=(\d+)\s+FAIL=(\d+)', line)
            if m:
                summary["total_pass"] = int(m.group(1))
                summary["total_fail"] = int(m.group(2))

            # FPGA ready
            if "FPGA-ready" in line:
                summary["fpga_ready"] = True
            if "FIX BEFORE FPGA DEPLOY" in line:
                summary["fpga_ready"] = False

            # Pixel stats
            m = re.search(r'PASS: (\d+) / (\d+)', line)
            if m:
                summary["pixels_ok"] = int(m.group(1))
                summary["pixels_fail"] = int(m.group(2)) - int(m.group(1))

            # ACK
            m = re.search(r'ACK received: (0x[0-9A-Fa-f]+)', line)
            if m:
                summary["ack"] = m.group(1)

            # Y sample
            m = re.search(r'Y\[0\.\.3\] = ([0-9a-f ]+)', line)
            if m:
                summary["y_sample"] = m.group(1)

    # If no hazard line seen, mark A6 as PASS (assertion didn't fire)
    if results["A6"]["status"] == "NOT_RUN" and summary["total_pass"] > 0:
        results["A6"]["status"] = "PASS"
        results["A6"]["details"].append("No Port A+B simultaneous write hazard detected")

    return results, summary, raw_lines


def render_html(results, summary, raw_lines):
    fpga_str = ("✅ FPGA-READY" if summary["fpga_ready"] is True
                else "❌ FAIL — FIX BEFORE FPGA" if summary["fpga_ready"] is False
                else "⏳ Not run yet")
    color = ("#27ae60" if summary["fpga_ready"] is True
             else "#c0392b" if summary["fpga_ready"] is False
             else "#888")

    rows = ""
    for aid, desc in ASSERTION_DESC.items():
        r = results[aid]
        st = r["status"]
        if st == "PASS":
            badge = '<span style="color:#27ae60;font-weight:bold">✅ PASS</span>'
        elif st == "FAIL":
            badge = '<span style="color:#c0392b;font-weight:bold">❌ FAIL</span>'
        else:
            badge = '<span style="color:#888">— N/A</span>'
        details_html = ""
        for d in r["details"][:3]:
            details_html += f'<div style="font-size:11px;color:#555">{d}</div>'
        rows += f"""
        <tr>
          <td style="font-weight:bold">[{aid}]</td>
          <td>{desc}</td>
          <td style="text-align:center">{badge}</td>
          <td>{details_html}</td>
        </tr>"""

    pixel_bar = ""
    if summary["pixels_ok"] + summary["pixels_fail"] > 0:
        total = summary["pixels_ok"] + summary["pixels_fail"]
        pct = 100 * summary["pixels_ok"] / total
        pixel_bar = f"""
        <div style="margin:12px 0">
          <b>Pixel accuracy:</b> {summary['pixels_ok']}/{total} ({pct:.1f}%)
          <div style="background:#eee;border-radius:4px;height:16px;width:100%;margin-top:4px">
            <div style="background:#27ae60;height:16px;border-radius:4px;width:{pct:.1f}%"></div>
          </div>
        </div>"""

    log_html = "\n".join(raw_lines[-200:]) if raw_lines else "(no log)"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>RISC-V VPU Simulation Report</title>
<style>
  body {{ font-family: Arial, sans-serif; max-width: 960px; margin: 32px auto; color: #222; }}
  h1   {{ color: #1F497D; }}
  table {{ border-collapse: collapse; width: 100%; margin-top: 16px; }}
  th   {{ background: #1F497D; color: white; padding: 8px 12px; text-align: left; }}
  td   {{ padding: 7px 12px; border-bottom: 1px solid #ddd; vertical-align: top; }}
  tr:hover {{ background: #f9f9f9; }}
  .banner {{ font-size: 22px; font-weight: bold; padding: 16px 24px;
             border-radius: 6px; margin: 20px 0;
             background: {color}22; border: 2px solid {color}; color: {color}; }}
  pre {{ background: #1e1e1e; color: #ddd; padding: 16px; border-radius: 6px;
         font-size: 11px; max-height: 400px; overflow-y: auto; }}
</style>
</head>
<body>
<h1>RISC-V VPU — Simulation Assertion Report</h1>
<p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} &nbsp;|&nbsp;
   Source: <code>{LOG_FILE}</code></p>

<div class="banner">{fpga_str}</div>

<table>
  <tr>
    <th width="60">ID</th><th>Assertion</th>
    <th width="100">Result</th><th>Details</th>
  </tr>
  {rows}
</table>

<div style="margin-top:20px">
  <b>Summary:</b> PASS={summary['total_pass']}  FAIL={summary['total_fail']}
  {f"&nbsp;|&nbsp; ACK={summary['ack']}" if summary['ack'] else ""}
  {f"&nbsp;|&nbsp; Y[0..3]={summary['y_sample']}" if summary['y_sample'] else ""}
</div>

{pixel_bar}

<h2 style="margin-top:32px">Raw Log (last 200 lines)</h2>
<pre>{log_html}</pre>
</body>
</html>"""


if __name__ == "__main__":
    results, summary, raw_lines = parse_log(LOG_FILE)
    html = render_html(results, summary, raw_lines)
    with open(OUT_HTML, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Report written to {OUT_HTML}")
    if summary["fpga_ready"] is True:
        print("STATUS: FPGA-READY")
    elif summary["fpga_ready"] is False:
        print("STATUS: FAIL")
    else:
        print("STATUS: Run simulation first")
