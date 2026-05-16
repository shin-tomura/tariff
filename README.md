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

## 🌍 Core Simulation Mechanics

### 1. Micro-Auctions (The Residents)
The world consists of 3 nations (USA, CHN, JPN) with 10 residents each. Every resident has an age, weight, and a multi-currency wallet. They bid on 4 essential resources (Food, Wood, Metal, Oil) in annual global auctions. If a resident's weight drops below 50kg due to deprivation, they enter structural starvation and abandon all bids except for Food. Residents pass away at age 10 and reincarnate, transferring wealth based on the nation's inheritance tax.

### 2. Macro-Feedback (DeFi-Style AMM Exchange)
There are no central banks. Exchange rates between currencies are physically determined by the liquidity pools of a **Constant-Product AMM (x * y = k)**, the same mathematical formula used by DeFi protocols like Uniswap. Persistent trade imbalances will physically drain a nation's foreign reserves, naturally triggering hyper-devaluation, defaults, and economic blockades when liquidity dries up.

### 3. Policy Levers (God Mode)
You have absolute control over national policies in real-time:
- **Dynamic Tariffs:** Set item-specific import tariffs from 0% to 1000%.
- **Helicopter Money:** Inject arbitrary amounts of cash directly into any economy.
- **Export Bans & Food Security:** Lock down resources or prioritize domestic food supply.
- **Inheritance Tax:** Adjust tax rates (0-100%) to regulate generational wealth distribution.

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