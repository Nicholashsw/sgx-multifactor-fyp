import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

np.random.seed(42)

# ── Common parameters ────────────────────────────────────────────────────────
S0    = 100.0     # initial price
mu    = 0.08      # drift (8% annual)
T     = 1.0       # 1 year horizon
N     = 252       # daily steps
dt    = T / N
n_paths = 5       # paths to plot
n_mc    = 10000   # paths for distribution analysis

t_grid = np.linspace(0, T, N + 1)

# ── 1. GEOMETRIC BROWNIAN MOTION ─────────────────────────────────────────────
def simulate_gbm(S0, mu, sigma, T, N, n_paths, seed=None):
    if seed is not None: np.random.seed(seed)
    dt = T / N
    Z = np.random.normal(size=(n_paths, N))
    log_returns = (mu - 0.5 * sigma**2) * dt + sigma * np.sqrt(dt) * Z
    log_S = np.log(S0) + np.cumsum(log_returns, axis=1)
    S = np.hstack([np.full((n_paths, 1), S0), np.exp(log_S)])
    return S

sigma_gbm = 0.25
gbm_paths    = simulate_gbm(S0, mu, sigma_gbm, T, N, n_paths,    seed=1)
gbm_paths_mc = simulate_gbm(S0, mu, sigma_gbm, T, N, n_mc,        seed=2)

# ── 2. CONSTANT ELASTICITY OF VARIANCE ───────────────────────────────────────
def simulate_cev(S0, mu, sigma, beta, T, N, n_paths, seed=None):
    """dS = mu*S dt + sigma * S^beta dW.  Euler-Maruyama with reflection at 0."""
    if seed is not None: np.random.seed(seed)
    dt = T / N
    S = np.zeros((n_paths, N + 1))
    S[:, 0] = S0
    Z = np.random.normal(size=(n_paths, N))
    for i in range(N):
        diffusion = sigma * np.power(np.maximum(S[:, i], 1e-8), beta)
        S[:, i+1] = S[:, i] + mu * S[:, i] * dt + diffusion * np.sqrt(dt) * Z[:, i]
        S[:, i+1] = np.maximum(S[:, i+1], 1e-8)
    return S

# beta = 0.7 to give visible leverage effect (vol up when price down)
sigma_cev = 0.25 * S0**(1 - 0.7)   # rescaled so initial vol matches GBM
beta = 0.7
cev_paths    = simulate_cev(S0, mu, sigma_cev, beta, T, N, n_paths,    seed=1)
cev_paths_mc = simulate_cev(S0, mu, sigma_cev, beta, T, N, n_mc,        seed=2)

# ── 3. HESTON STOCHASTIC VOLATILITY ──────────────────────────────────────────
def simulate_heston(S0, mu, v0, kappa, theta, xi, rho, T, N, n_paths, seed=None):
    """
    dS = mu*S dt + sqrt(v) * S dW_S
    dv = kappa*(theta - v) dt + xi*sqrt(v) dW_v
    corr(dW_S, dW_v) = rho dt
    Full truncation Euler scheme — robust, standard.
    """
    if seed is not None: np.random.seed(seed)
    dt = T / N
    S = np.zeros((n_paths, N + 1))
    v = np.zeros((n_paths, N + 1))
    S[:, 0] = S0
    v[:, 0] = v0
    Z1 = np.random.normal(size=(n_paths, N))
    Z2 = np.random.normal(size=(n_paths, N))
    W_v = Z1
    W_S = rho * Z1 + np.sqrt(1 - rho**2) * Z2
    for i in range(N):
        v_pos = np.maximum(v[:, i], 0.0)
        v[:, i+1] = v[:, i] + kappa * (theta - v_pos) * dt + xi * np.sqrt(v_pos) * np.sqrt(dt) * W_v[:, i]
        S[:, i+1] = S[:, i] * np.exp((mu - 0.5 * v_pos) * dt + np.sqrt(v_pos) * np.sqrt(dt) * W_S[:, i])
    return S, v

v0     = 0.0625      # initial variance (vol = 25%)
kappa  = 2.0         # mean reversion speed
theta  = 0.0625      # long-run variance (vol = 25%)
xi     = 0.5         # vol of vol
rho    = -0.7        # leverage effect

heston_paths,    heston_v    = simulate_heston(S0, mu, v0, kappa, theta, xi, rho, T, N, n_paths, seed=1)
heston_paths_mc, heston_v_mc = simulate_heston(S0, mu, v0, kappa, theta, xi, rho, T, N, n_mc,    seed=2)

# ── DIAGNOSTICS ──────────────────────────────────────────────────────────────
def diagnostics(paths, name):
    log_ret = np.diff(np.log(paths), axis=1).flatten()
    return {
        "Model": name,
        "Mean (ann)":   np.mean(log_ret) * 252,
        "Vol (ann)":    np.std(log_ret) * np.sqrt(252),
        "Skew":         pd.Series(log_ret).skew(),
        "Kurt (excess)":pd.Series(log_ret).kurtosis(),
        "P(S_T < S_0)": np.mean(paths[:, -1] < S0),
        "VaR 95%":      np.percentile(paths[:, -1], 5),
        "VaR 99%":      np.percentile(paths[:, -1], 1),
    }

stats = pd.DataFrame([
    diagnostics(gbm_paths_mc,    "GBM"),
    diagnostics(cev_paths_mc,    f"CEV (β={beta})"),
    diagnostics(heston_paths_mc, "Heston"),
])
print(stats.to_string(index=False, float_format=lambda x: f"{x:.4f}"))

# ── PLOT ─────────────────────────────────────────────────────────────────────
plt.style.use("default")
fig = plt.figure(figsize=(15, 11), facecolor="white")
gs = GridSpec(3, 3, figure=fig, hspace=0.45, wspace=0.30)

NAVY  = "#0D1B2A"
TEAL  = "#1B7F79"
AMBER = "#E8A838"
COLS  = ["#0D1B2A", "#1B7F79", "#E8A838", "#C0392B", "#7D3C98"]

def style_ax(ax, title, ylabel="Price ($)", xlabel="Time (years)"):
    ax.set_title(title, fontsize=11, color=NAVY, fontweight="bold", pad=10)
    ax.set_xlabel(xlabel, fontsize=9, color="#444")
    ax.set_ylabel(ylabel, fontsize=9, color="#444")
    ax.grid(True, linestyle=":", color="#bbb", alpha=0.6)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    for s in ["bottom", "left"]:
        ax.spines[s].set_color("#888")
    ax.tick_params(colors="#444", labelsize=8)

# Row 1: paths
for j, (paths, name) in enumerate([(gbm_paths, "Geometric Brownian Motion"),
                                   (cev_paths, f"CEV Model (β = {beta})"),
                                   (heston_paths, "Heston Stochastic Volatility")]):
    ax = fig.add_subplot(gs[0, j])
    for i in range(n_paths):
        ax.plot(t_grid, paths[i], color=COLS[i], linewidth=1.5, alpha=0.85)
    ax.axhline(S0, color="#888", linestyle="--", linewidth=0.8, alpha=0.7)
    style_ax(ax, name)

# Row 2: terminal price distributions
for j, (paths, name) in enumerate([(gbm_paths_mc,    "GBM"),
                                   (cev_paths_mc,    f"CEV (β = {beta})"),
                                   (heston_paths_mc, "Heston")]):
    ax = fig.add_subplot(gs[1, j])
    terminal = paths[:, -1]
    ax.hist(terminal, bins=80, color=TEAL, alpha=0.75, edgecolor="white", linewidth=0.3)
    ax.axvline(S0,                color="#888",  linestyle="--", linewidth=0.8)
    ax.axvline(np.mean(terminal), color=AMBER,    linestyle="-",  linewidth=1.5, label=f"Mean {np.mean(terminal):.1f}")
    ax.axvline(np.percentile(terminal, 5),  color="#C0392B", linestyle=":", linewidth=1.5, label="5% VaR")
    ax.legend(fontsize=7, frameon=False)
    style_ax(ax, f"{name} — Terminal Price Distribution",
             ylabel="Frequency", xlabel="$S_T$ ($)")

# Row 3: Heston instantaneous variance + log-return distributions overlay
ax_v = fig.add_subplot(gs[2, 0])
for i in range(n_paths):
    ax_v.plot(t_grid, np.sqrt(np.maximum(heston_v[i], 0)) * 100, color=COLS[i], linewidth=1.5, alpha=0.85)
ax_v.axhline(np.sqrt(theta) * 100, color="#888", linestyle="--", linewidth=0.8, label=f"Long-run σ = {np.sqrt(theta)*100:.1f}%")
ax_v.legend(fontsize=8, frameon=False)
style_ax(ax_v, "Heston — Instantaneous Volatility Paths",
         ylabel="Volatility (% annualised)", xlabel="Time (years)")

# Log-returns overlay
ax_r = fig.add_subplot(gs[2, 1:])
for paths, name, color in [(gbm_paths_mc,    "GBM",                NAVY),
                           (cev_paths_mc,    f"CEV (β = {beta})", TEAL),
                           (heston_paths_mc, "Heston",             AMBER)]:
    log_ret = np.diff(np.log(paths), axis=1).flatten()
    ax_r.hist(log_ret, bins=120, color=color, alpha=0.45, density=True,
              label=name, edgecolor="none")
style_ax(ax_r, "Daily Log-Return Distributions Compared",
         ylabel="Density", xlabel="Log return")
ax_r.legend(fontsize=9, frameon=False)
ax_r.set_xlim(-0.06, 0.06)

fig.suptitle("Computer-Generated Asset Price Simulations: GBM vs CEV vs Heston",
             fontsize=14, color=NAVY, fontweight="bold", y=0.995)
fig.text(0.5, 0.005,
         f"S₀={S0}, μ={mu}, T={T}yr, {N} steps, {n_mc:,} MC paths   "
         f"|   Heston: κ={kappa}, θ={theta}, ξ={xi}, ρ={rho}",
         ha="center", fontsize=8, color="#666", style="italic")

plt.savefig("/home/claude/sim/simulations.png", dpi=140, bbox_inches="tight", facecolor="white")
print("Saved: /home/claude/sim/simulations.png")

# Save stats CSV too
stats.to_csv("/home/claude/sim/diagnostics.csv", index=False)
print("Saved: /home/claude/sim/diagnostics.csv")