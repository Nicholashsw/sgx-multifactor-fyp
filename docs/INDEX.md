# Quant Reading List — STI-Alpha FYP & Hedge Fund Path

Sixteen open-access PDFs covering everything from Markowitz's 1952 foundation through machine-learning asset pricing. Ordered by suggested reading sequence, not chronologically. Each entry says **why** you're reading it — for the FYP, for interviews, or for the longer fund-building arc.

Built for educational and research purposes. Not financial advice.

---

## TIER 1 — Foundations · read these first, no exceptions

These four define the language every quant interview uses. Skip none.

### 01 — Fama & MacBeth (1973), *Risk, Return, and Equilibrium: Empirical Tests*
**Why:** The cross-sectional two-pass regression you'll use in FYP Module 1. This *is* the FYP method. Learn the Shanken correction, errors-in-variables, why the second-pass uses time-series averages of cross-sectional coefficients.
**Patricia-relevance:** High. Directly her scope.

### 02 — Markowitz (1952), *Portfolio Selection*
**Why:** The grandfather paper. Mean-variance optimisation, the efficient frontier, why diversification works mathematically. Cited in every portfolio construction interview.
**Patricia-relevance:** Foundational; aligns with Rice Portfolio Management course she sent.

### 03 — Fama & French (1993), *Common Risk Factors in the Returns on Stocks and Bonds*
**Why:** The three-factor model. SMB, HML, market. Every multi-factor SGX model you'll build is a descendant. 50+ pages — read it twice.
**Patricia-relevance:** Very high. This is the model you're extending.

### 04 — Jegadeesh & Titman (1993), *Returns to Buying Winners and Selling Losers*
**Why:** The momentum factor. 12-1 month, 6-1 month — your FYP momentum cluster comes from here.
**Patricia-relevance:** High. Standard factor.

---

## TIER 2 — Factor Zoo & Modern Anomalies · core FYP reading

The factors you'll construct in Module 1 trace to these.

### 05 — Carhart (1997), *On Persistence in Mutual Fund Performance*
**Why:** The four-factor model (FF3 + momentum). Also the canonical paper on survivorship bias in fund performance — directly relevant to your PIT universe construction.
**Patricia-relevance:** High.

### 06 — Sloan (1996), *Do Stock Prices Fully Reflect Information in Accruals and Cash Flows?*
**Why:** The accruals factor. One of the strongest anomalies ever documented. Earnings persistence framework still cited in 2026.
**Patricia-relevance:** Medium. Builds your quality cluster.

### 07 — Novy-Marx (2013), *The Other Side of Value: Gross Profitability Premium*
**Why:** Gross profits / assets, the modern profitability factor. AQR uses this. Cleaner signal than ROE.
**Patricia-relevance:** Medium-high. Quality factor construction.

### 08 — Frazzini & Pedersen (2014), *Betting Against Beta*
**Why:** Low-vol / BAB factor. Theoretical foundation for leverage-constrained investors bidding up high-beta names. Your low-vol cluster.
**Patricia-relevance:** Medium-high. Builds low-vol factor.

### 09 — Asness, Frazzini & Pedersen (2019), *Quality Minus Junk*
**Why:** QMJ — the composite quality factor combining profitability, growth, safety, payout. The reference quality construction.
**Patricia-relevance:** High. Direct factor construction reference.

---

## TIER 3 — Replication Crisis & Statistical Rigour · read before claiming significance

These two will save you from the most embarrassing examiner question: *"How do you know your factors aren't false positives?"*

### 10 — Harvey, Liu & Zhu (2016), *…and the Cross-Section of Expected Returns*
**Why:** Multiple-testing in factor research. Why t=2.0 is no longer enough. You'll cite Bonferroni-corrected hurdles directly from this in your FYP.
**Patricia-relevance:** High. Robustness chapter material.

### 11 — Hou, Xue & Zhang (2020), *Replicating Anomalies*
**Why:** 452 anomalies tested; 65% fail to replicate under rigorous standards. The most damning paper on the factor zoo. Honest framing for your FYP — most factors don't survive.
**Patricia-relevance:** Medium-high. Lit-review backbone.

---

## TIER 4 — Risk Modelling · FYP Module 2 core

The hardest module, the highest-leverage signal to quant interviewers.

### 12 — Menchero, Orr & Wang (2011), *The Barra US Equity Model (USE4) Methodology Notes*
**Why:** MSCI's official documentation of the BARRA risk model. Bias statistic, eigenfactor risk adjustment, volatility regime adjustment. Read this and you can hold a credible BARRA conversation with anyone at AQR or Schonfeld.
**Patricia-relevance:** Lower (beyond her stated scope, but acceptable as risk-model extension).

### 13 — Ledoit & Wolf (2004), *Honey, I Shrunk the Sample Covariance Matrix*
**Why:** Why never to use raw sample covariance in optimisation. Shrinkage estimator with explicit formula. Combine with BARRA factor covariance for the best of both.
**Patricia-relevance:** Medium. Portfolio construction quality.

---

## TIER 5 — Modern Methods · ML, execution, regimes

For Modules 3 (HMM), 4 (XGBoost), 5 (execution costs).

### 14 — Gu, Kelly & Xiu (2020), *Empirical Asset Pricing via Machine Learning*
**Why:** The reference paper for ML in asset pricing. Compares ridge, lasso, random forest, gradient boost, neural nets across 30,000+ US stocks. Frame your XGBoost work against this. Note their conclusion: **trees and NNs beat linear, but not by much, and gains come from non-linear interactions.**
**Patricia-relevance:** Lower (stretch chapter material).

### 15 — Almgren & Chriss (2000), *Optimal Execution of Portfolio Transactions*
**Why:** The square-root market impact model. Capacity analysis. Why you can't deploy $1bn into a strategy backtested with zero costs. Cited in every execution interview.
**Patricia-relevance:** Lower. Module 5 extension.

### 16 — Hamilton (2005), *Regime-Switching Models* (survey)
**Why:** The canonical reference for Markov-switching / HMM regime detection in finance. Foundational paper is Hamilton (1989, Econometrica) but it's paywalled; this survey by the same author covers the same ground with updates. Read this for Module 3.
**Patricia-relevance:** Lower. Module 3 extension.

---

## Suggested Reading Plan

### Week 1-2 (now): Tier 1
The four foundations. Take notes. These four papers alone justify 50% of your FYP literature review.

### Week 3-4: Tier 2
Factor zoo. Cross-reference each with the factor cluster you're building (value, momentum, quality, low-vol).

### Week 5: Tier 3
Statistical rigour. Reset your significance hurdle to t > 3.0 after reading these.

### Week 6-7: Tier 4
Risk modelling. The Menchero paper alone takes a week. Do not rush it.

### Week 8+: Tier 5
Only after Tiers 1-4 are absorbed. These are extensions, not core.

---

## What's deliberately not in this bundle

- **Black-Scholes / options pricing**: not relevant to FYP scope.
- **Tick-data microstructure**: not relevant to monthly equity factor work.
- **DeFi / crypto**: noise; come back to it after building one thing well.
- **VAR / VECM econometrics**: covered in your independent macro research work; don't double up.
- **LSTM / deep learning**: data volume too small for SGX; XGBoost is the right tool.

---

## After these 16: where to go next

If you finish all sixteen and want more:
- **Cochrane, *Asset Pricing*** (2005 book) — the unified theoretical framework.
- **Grinold & Kahn, *Active Portfolio Management*** (2000) — practitioner's bible for active equity.
- **Lopez de Prado, *Advances in Financial Machine Learning*** (2018) — purged CV, meta-labelling. Book, not free, but ~$50.
- **Pedersen, *Efficiently Inefficient*** (2015) — interviews with PMs about their actual strategies.

But finish the sixteen first.

---

*Nicholas Hong | Built for educational and research purposes. Not financial advice.*
