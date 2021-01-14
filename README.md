# Multireflection Time-of-Flight Mass Spectrometer

This repository is part of an MR-ToF project for the mass spectrometry of superheavy nuclei at the University of Groningen.
It collects all the relevant files for the ion dynamics simulations at low energies with [SIMION](https://simion.com/).

## Prerequisite
The development environment is **SIMION 8.1.2.30-TEST-2017-02-01**.

## Usage
1. Generate potential arrays by running in command line: `lua.exe main.lua`.
1. Load the potential arrays (`.pa0` file) in SIMION.
1. View the workbench and save it as an `.iob` file.
1. Define particles by loading the `.fly2` file.
1. Fly the ions.

## License
This repository is licensed under the **GNU GPLv3**.
