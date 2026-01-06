# Security in Software Applications – Echidna Project

This repository contains the project for the course
**Security in Software Applications (2025/2026)**.

## Structure
- `contracts/`: Solidity contracts and Echidna test harnesses
- `report/`: final report (PDF) and screenshots

## Tool
The project uses **Echidna** as a property-based fuzzing tool:
https://github.com/crytic/echidna

## How to run Echidna
Example:

```bash
cd contracts
echidna TestTaxpayer.sol
