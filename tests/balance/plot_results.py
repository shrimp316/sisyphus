"""Optional static report figure. Requires matplotlib; aggregation is stdlib-only."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    summary = json.loads(args.summary.read_text(encoding="utf-8"))
    groups = [g for g in summary["single_groups"]
              if g["job_id"].startswith("baseline_") and g["growth_mode"] == "actual"]
    colors = {"novice": "#b84535", "regular": "#28788a", "skilled": "#527448", "optimized": "#8a6499"}
    labels = {"novice": "Novice policy", "regular": "Regular policy", "skilled": "Skilled policy", "optimized": "120 Hz oracle policy"}
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5), constrained_layout=True)
    fig.set_facecolor("#faf9f5")
    for policy in colors:
        rows = sorted((g for g in groups if g["policy"] == policy), key=lambda g: g["level"])
        x = [g["level"] for g in rows]
        axes[0].plot(x, [100 * g["completion_by_cap"]["rate"] for g in rows], marker="o", color=colors[policy], label=labels[policy], alpha=.85)
        axes[1].plot(x, [g["peak_m"]["mean"] for g in rows], marker="o", color=colors[policy], label=labels[policy], alpha=.85)
    for ax in axes:
        ax.set_facecolor("#faf9f5")
        ax.spines[["top", "right"]].set_visible(False)
        ax.set_xlabel("Rank in each of the three existing upgrades")
        ax.set_xticks([0, 3, 5, 8, 10])
        ax.grid(axis="y", alpha=.18)
    axes[0].set_title("Summits by run time limit")
    axes[0].set_ylabel("Observed completion (%)")
    axes[0].set_ylim(-4, 105)
    axes[1].set_title("Mean furthest route distance")
    axes[1].set_ylabel("Route distance (m)")
    axes[1].set_ylim(0, 1050)
    axes[1].legend(loc="lower right", frameon=False, fontsize=8)
    fig.suptitle("SISYPHUS ACT I — CURRENT SYSTEM PILOT\nSynthetic policies; three paired seeds per cell; not human completion rates", fontsize=12)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=180)
    plt.close(fig)
    print(args.output)


if __name__ == "__main__":
    main()
