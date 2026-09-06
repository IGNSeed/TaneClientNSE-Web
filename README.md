# TaneClient NSE Web

Official download site and stable update manifest for TaneClient on Minecraft: Nintendo Switch Edition.

The site is intentionally dependency-free: HTML, CSS, and vanilla JavaScript are deployed directly to GitHub Pages. Release binaries are never committed to this repository. They are published only as explicitly approved GitHub Release assets.

## Local preview

From the repository root, start any static HTTP server. For example:

```powershell
python -m http.server 8080
```

Then open `http://localhost:8080/`. Run the repository checks with:

```powershell
python scripts/verify-site.py
```

## Deployment

`.github/workflows/deploy-pages.yml` verifies the site, builds a narrow Pages artifact containing only `index.html`, `update.json`, `.nojekyll`, and `assets/`, then deploys it through the official GitHub Pages Actions. The public stable manifest is:

```text
https://ignseed.github.io/TaneClientNSE-Web/update.json
```

`update.json` is consumed by the Release client. Its schema is strict and must contain only `schema`, `version`, `channel`, and the `subsdk4` / `main_npdm` asset records expected by the client parser. Web-only release data belongs in `assets/site-data.js`, never in `update.json`.

## Preparing a release locally

The preparation helper creates an ignored staging directory, the SD-card-ready ZIP, hashes, byte sizes, and a candidate `update.json`. It never uploads anything.

```powershell
.\scripts\prepare-release.ps1 `
  -SourceReleaseDirectory '..\TaneClient\out\release' `
  -Version '1.0.0'
```

The generated files are placed under `.release/v1.0.0/`. Before publishing, run the actual TaneClient manifest parser against the generated manifest and copy the verified manifest to the repository root.

## Future release procedure

1. Update the TaneClient version.
2. Build and verify the Release target.
3. Obtain explicit user permission to publish that Release's artifacts.
4. Prepare `subsdk4`, `main.npdm`, and the SD-card ZIP locally.
5. Compute and verify exact SHA-256 hashes and byte sizes.
6. Create the GitHub Release with only the explicitly approved assets.
7. Update the strict root `update.json` and `assets/site-data.js`.
8. Deploy GitHub Pages.
9. Re-download and verify the manifest, asset URLs, sizes, hashes, and website download link.

Explicit permission is required for every Release artifact upload. Permission for one version must never be reused for a later version. Development binaries, build directories, ELF/map/object files, logs, reverse-engineering data, and any unapproved assets must never be published.

