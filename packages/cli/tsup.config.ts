import { defineConfig } from "tsup";

export default defineConfig({
    entry: ["src/index.ts", "src/bin.ts"],
    format: ["esm"],
    dts: {
        resolve: ["@photokit-node/core"],
    },
    clean: true,
    sourcemap: true,
    noExternal: ["@photokit-node/core"],
});
