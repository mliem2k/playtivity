const fs = require("fs");
const path = require("path");

// version.yml holds "version: NAME+BUILD", the single source the release scripts rewrite.
const line = fs.readFileSync(path.join(__dirname, "version.yml"), "utf8").match(/^version:\s*(\S+)/m)[1];
const [version, build] = line.split("+");

module.exports = {
  expo: {
    name: "Playtivity",
    slug: "playtivity",
    scheme: "playtivity",
    version,
    orientation: "portrait",
    userInterfaceStyle: "dark",
    icon: "./assets/images/playtivity_logo.png",
    newArchEnabled: true,
    plugins: ["expo-router", "expo-secure-store", "./plugins/withReleaseSigning"],
    experiments: { typedRoutes: true },
    android: { package: "com.mliem.playtivity", versionCode: Number(build) || 1 },
    ios: { bundleIdentifier: "com.mliem.playtivity" },
  },
};
