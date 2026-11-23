# TerraBound SAR

> Project description coming soon.

## Project structure

```
Backend/    Node.js + Express API (not started yet)
Frontend/   React app built with Vite
makefile    Shortcuts for installing and running both apps
```

## Prerequisites

- **Node.js** 18 or higher (includes npm)
- **Git**
- **Make** (optional, see below)

### Installing Make on Windows

1. Download and install [GnuWin Make](https://gnuwin32.sourceforge.net/packages/make.htm).
2. Add its `bin` folder (for example `C:\Program Files (x86)\GnuWin32\bin`) to your `Path` environment variable.
3. Open a new terminal and check that it works:

   ```sh
   make --version
   ```

## Getting started

Install the dependencies for both apps:

```sh
make install
```

Start the frontend dev server:

```sh
make frontend-dev
```

Without Make, run the same steps with npm:

```sh
cd Frontend
npm install
npm run dev
```
