# Hakoniwa Tariff: AMM Macroeconomics Sandbox

A brutally transparent, minimalist macroeconomic sandbox built with Flutter. There are no scripted events, no central banks, and no invisible hands—just pure math, micro-behaviors, and the chaotic emergent phenomena of international trade.

The simulation engine is highly optimized and includes memory-efficient rolling windows, allowing it to run for over 10,000 years offline on mobile devices with zero memory leaks.

---

## ⚠️ A Note on Contributions & Community (Please Read)

This repository is published strictly for **transparency and educational purposes**. I want players and economics enthusiasts to be able to verify the AMM formulas and see exactly how the macroeconomic engine works behind the scenes.

Because I am a solo developer fully focused on my own vision, **Issues and Pull Requests are completely disabled**. I do not accept code contributions, feature requests, or bug reports here.

However, the **Discussions** tab is wide open! I highly encourage you to use it to:
- Discuss the emergent economic behaviors you discover.
- Share your custom crisis scenarios using the app's lightweight Base64 save-code feature.
- Talk about trade policies, tariffs, or even roast my spaghetti code.

Feel free to hang out and discuss among yourselves!

---

## 🧱 Design Philosophy & Axioms

This simulator is not a faithful reproduction of real-world economics. It is a **deliberately simplified model** built on a fixed set of axioms. Understanding these axioms is the key to understanding why the simulation behaves the way it does—and why certain design decisions that look like bugs are intentional.

### The Core Axioms

| Axiom | What it means |
|---|---|
| **Residents hold only local currency** | Citizens cannot accumulate foreign currency. There is no private FX market. |
| **All international trade clears through the Global AMM** | There is no bilateral deal-making. Exchange rates are purely pool-ratio-determined. |
| **Exporting does not yield foreign currency** | Export revenue flows into government reserves as local currency, not foreign currency. |
| **Foreign reserves accumulate only via Currency Intervention** | The government must actively sell local currency into the AMM to acquire foreign reserves. |
| **UBI is distributed in local currency only** | The government cannot distribute foreign reserves directly to residents. |
| **Physical assets seized via inheritance tax re-enter domestic supply** | Confiscated Wood, Metal, and Oil are recycled back into the market, not destroyed. |
| **Food Domestic Priority unconditionally front-queues domestic buyers** | In food auctions, domestic residents are sorted ahead of foreign buyers regardless of WTP. |

These axioms produce a world of **extreme state-managed economies**, where currency strength is the primary lever of national power, and residents experience the macroeconomy only through UBI and local market prices—never directly through trade.

### What This Model Deliberately Ignores

- Private capital flows and foreign direct investment
- Central bank interest rate policy
- Resident-level foreign exchange access
- Corporate entities distinct from residents

This is not a limitation—it is the model. If you came here looking for a general-purpose economic simulator, this is not that. If you are curious what happens when you reduce international economics to its most mechanical skeleton, you are in the right place.

### A Note on the Multi-Currency Wallet

Residents have a multi-currency wallet in the data model, but under current axioms, holding foreign currency provides no advantage—all trade clears through the AMM regardless. The wallet structure exists as **scaffolding for future expansion** and is documented here to prevent it from being mistaken for a bug.

---

## 🌍 Core Simulation Mechanics

### 1. Micro-Auctions (The Residents)

The world consists of 3 nations (USA, CHN, JPN) with 10 residents each. Every resident has an age, weight, and a multi-currency wallet. They bid on 4 essential resources (Food, Wood, Metal, Oil) in annual global auctions.

If a resident's weight drops below 50kg due to deprivation, they enter structural starvation and abandon all bids except for Food. Residents pass away at age 10 and reincarnate, transferring wealth based on the nation's inheritance tax rate.

### 2. Macro-Feedback (DeFi-Style AMM Exchange)

There are no central banks. Exchange rates between currencies are physically determined by the liquidity pools of a **Constant-Product AMM (x · y = k)**—the same mathematical formula used by DeFi protocols like Uniswap.

Persistent trade imbalances will physically drain a nation's foreign reserves, naturally triggering hyper-devaluation, defaults, and economic blockades when liquidity dries up.

### 3. Food Auction: Two-Round Structure

Food auctions run in two sequential rounds:

**Round 1 — Global auction.** All buyers worldwide submit bids. If Food Domestic Priority is enabled, domestic residents are unconditionally sorted to the front of the queue, ahead of all foreign buyers regardless of willingness to pay. Winners are determined by available supply.

**Round 2 — Domestic safety net (always active).** If food remains after Round 1, a second auction is held exclusively for domestic residents who failed to secure food in Round 1. The clearing price in Round 2 is capped at the Round 1 clearing price, meaning domestic residents who missed Round 1 can still buy at a protected lower price. **This round activates regardless of the Food Domestic Priority setting**—it is a structural feature of the simulation, not a policy toggle.

### 4. Policy Levers (God Mode)

You have absolute control over national policies in real-time:

- **Dynamic Tariffs:** Set item-specific import tariffs from 0% to 1000%.
- **Helicopter Money:** Inject arbitrary amounts of cash directly into any economy.
- **Export Bans & Food Security:** Lock down resources or prioritize domestic food supply.
- **Inheritance Tax:** Adjust tax rates (0–100%) to regulate generational wealth distribution.
- **Currency Intervention:** Sell local currency into the AMM to acquire foreign reserves (devaluation), or sell foreign reserves to defend currency value (revaluation).
- **UBI Payout Ratio & Mode:** Choose between flat (universal) and progressive (HWI-weighted inverse) distribution of government reserves to residents.

---

## 📐 Key Formulas

### AMM Swap (Constant-Product)

```
ΔY = (Y · ΔX) / (X + ΔX)
```

Where X and Y are the liquidity pool sizes of the two currencies being swapped, and ΔX is the input amount. This is the canonical Uniswap v1 formula with no fees.

### Holistic Welfare Index (HWI)

Each resident's welfare is scored as:

HWI = AssetScore + HealthScore + FinancialScore

AssetScore     = (woodStock × Weight_W) + (metalStock × Weight_M) + (oilStock × Weight_O)
Weight_R       = (TotalGlobalDemand / GlobalSupply) × (100 / AnnualConsumption_R) × 4.0
HealthScore    = max(0, (weight − 50) × 100)
FinancialScore = 1000 × log₂(1 + max(0, residentWealth / avgNationalWealth))

* **Weight_R:** The weight of each resource is dynamic. Resources that are rarer or represent a higher proportion of global consumption carry significantly more weight.
* **HWI Usage:** HWI is used for Gini index calculation and progressive UBI weighting. In progressive mode, each resident's UBI share is proportional to `1 / max(1, HWI)`, redistributing wealth toward the least wealthy.

---

## 🔒 Privacy Policy

This Privacy Policy applies to the **Hakoniwa Tariff** mobile application.

### 1. Data Collection and Usage
- **Zero Personal Data Collection:** This application does not collect, store, track, or transmit any personal data, device identifiers, or usage statistics.
- **100% Offline & Local:** The simulation runs entirely on your local device. All game progress and configuration parameters are stored locally using an encrypted/compact on-device database (Hive). No data ever leaves your device.
- **No Third-Party SDKs:** The app does not integrate with any third-party analytics, tracking tools, or advertising networks.

### 2. Permissions
- **File System / Storage:** The app utilizes the standard OS file picker solely when you explicitly choose to export or import your full backup files (`.hknw`). It does not read or access any other files on your device.

### 3. Changes to this Policy
Since the app collects no data, this privacy policy is static. If any future updates introduce network features, this policy will be updated accordingly.

---

## 📄 License

This project is licensed under the MIT License - see the source files for details.

---

## 🔄 Changelog

### v1.0.6
- **Added Clear Inventory Feature (Advance Edit):** Added a function to the Advanced Edit screen that resets the inventories of all nations and all citizens to zero for each of the three resources: Wood, Metal, and Oil.
- **Added License List Link:** Placed a link to the License List screen at the bottom of the Rules screen.

### v1.0.5
- **Enhanced Dashboard UI:** Added real-time visibility for "Targeted Export Bans" directly on each country's dashboard card. The layout has also been optimized with flexible text wrapping to prevent UI overflow errors on devices using larger accessibility font scales.
- **Updated In-Game Rules:** Completely revised the "Rules & Specifications" screen (in both English and Japanese) to accurately describe the latest multi-round auction mechanics. It now explicitly details the 4th-round domestic bailout system for food, starvation penalties, and quality multiplier debuffs, while removing outdated descriptions.
- **Fixed Domestic Bailout Logic:** Resolved a critical bug in the 4th-round food auction where residents were unintentionally blocked from participating in the domestic bailout if they had already bid and lost in their home market during Rounds 1-3.

### v1.0.4
- **Supply Chain Degradation:** Introduced resource quality debuffs in the multi-round auction system. Procuring resources in later bidding rounds now yields reduced effective quantities (e.g., 85% in Round 2, 70% in Round 3), simulating the harsh realities of secondary markets and economic sanctions.
- **Gradual Starvation Model:** Overhauled the resident weight management logic. Weight gain/loss is now calculated continuously using linear interpolation based on the food fulfillment ratio, allowing for highly realistic simulations of chronic malnutrition and gradual physical decline.

### v1.0.3
- **⚠️ Important Notice:** Due to major structural changes in the simulation engine and data models, this version is not compatible with save data from v1.0.2 or earlier. Please perform a fresh installation or clear your local app data after updating to avoid potential crashes.
- **Targeted Sanctions:** Added the ability to impose item-specific export embargos on specific countries to simulate geopolitical trade policies.
- **Multi-Round Trade Engine:** Implemented a multi-round bidding system (up to 4 rounds for Food, 3 for others) to enable spatial arbitrage and reduce market volatility.
- **Dynamic Macroeconomic Weighting:** Asset valuation in HWI is now dynamic based on supply, demand, and scarcity.

### v1.0.2
- App Store Release.

