# Contributing to FujiRecipes for macOS

Thank you for your interest in contributing to FujiRecipes! We welcome bug reports, feature suggestions, code contributions, and new film recipe formulations.

---

## Code of Conduct

We are committed to providing a welcoming, friendly, and inclusive environment for everyone. Please be respectful and constructive in all issues, pull requests, and discussions.

---

## How to Contribute

### 1. Reporting Bugs
- Before filing a bug, check existing [Issues](https://github.com/AntApper/FujiRecipesMac/issues) to avoid duplicates.
- Use the **Bug Report** template and include your camera model, firmware version, macOS version, and steps to reproduce.

### 2. Suggesting Features & Recipes
- For UI or protocol enhancements, use the **Feature Request** template.
- For new film recipe formulations to add to the curated library, use the **Recipe Suggestion** template.

### 3. Submitting Pull Requests
1. Fork the repository and create your feature branch:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Build and verify test suites:
   ```bash
   swift test --package-path FujiRecipesCore
   swift test --package-path FujiPTPClient
   python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
   ```
3. Commit your changes with clear, concise messages.
4. Push to your fork and submit a Pull Request against the `main` branch.

---

## Hardware Safety Guidelines

When contributing camera protocol or PTP communication code:
- Never overwrite custom dial slots (C1–C7) without readback verification and rollback safety fixtures.
- Adhere strictly to the documented scopes in [docs/RELEASE.md](docs/RELEASE.md) and [docs/MACOS_RELEASE_BOUNDARIES.md](docs/MACOS_RELEASE_BOUNDARIES.md).
