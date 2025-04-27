import csv
import matplotlib.pyplot as plt

def draw_gantt(csv_path, title, out_png):
    events = []                       # list of (pid, start, dur)
    with open(csv_path) as f:
        reader = csv.reader(f)
        for pid, start, dur in reader:
            events.append((int(pid), int(start), int(dur)))

    # make contiguous
    events.sort(key=lambda e: e[1]) 

    merged = []
    for pid, start, dur in events:
        if (merged
            and merged[-1][0] == pid
            and start == merged[-1][1] + merged[-1][2]):      # contiguous
            prev_pid, prev_start, prev_dur = merged[-1]
            merged[-1] = (pid, prev_start, prev_dur + dur)    # extend bar
        else:
            merged.append((pid, start, dur))

    events = merged

    events.sort(key=lambda e: e[1])

    fig, ax = plt.subplots(figsize=(10, 2.5))
    y = 0                              # single horizontal lane
    for pid, start, dur in events:
        ax.barh(y, dur, left=start,
                height=0.6, edgecolor='black')
        ax.text(start + dur/2, y,
                f'{pid}',
                va='center', ha='center', color='white', fontsize=9)

    ax.set_xlabel('Time (ticks)')
    ax.set_yticks([])
    ax.set_title(title)
    ax.set_xlim(0, max(s+ d for _,s,d in events) + 1)
    fig.tight_layout()
    fig.savefig(out_png, dpi=150)
    print(f"Saved {out_png}")




draw_gantt('timeline_FCFS.csv', 'FCFS Gantt (seed 12345678)', 'fcfs_gantt.png')
draw_gantt('timeline_RoundRobin.csv', 'Round-Robin q=8', 'rr_gantt.png')
draw_gantt('timeline_SJF.csv', 'SJF (non-preemptive)', 'sjf_gantt.png')
draw_gantt('timeline_SRTF.csv', 'SRTF (pre-emptive SJF)', 'srtf_gantt.png')