# CPU-Scheduling Simulator (Zig 0.13.0)  
_CS 3502 - Project 2_

![Zig](https://img.shields.io/badge/zig-0.13.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

A fast, cross-platform console tool that simulates four classic CPU-scheduling
algorithms, outputs detailed metrics, and produces timeline data you can turn
into Gantt charts.

| Algorithm | Type | Notes |
|-----------|------|-------|
| FCFS      | non-preemptive | baseline arrival-order queue |
| SJF       | non-preemptive | shortest burst first |
| Round Robin (q = 8) | pre-emptive | linked-list ready queue |
| SRTF      | pre-emptive    | 1-tick shortest-remaining-time |

---

## 1  Build & Run
`zig build run && python src/pyplot.py`\
this will create tables in console and gantt chart images

