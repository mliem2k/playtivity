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
    plugins: [
      "expo-router",
      "expo-secure-store",
      [
        "expo-font",
        {
          fonts: [
            "./assets/fonts/Montserrat-Regular.ttf",
            "./assets/fonts/Montserrat-Medium.ttf",
            "./assets/fonts/Montserrat-SemiBold.ttf",
            "./assets/fonts/Montserrat-Bold.ttf",
            "./assets/fonts/Montserrat-ExtraBold.ttf",
          ],
        },
      ],
      [
        "react-native-android-widget",
        {
          widgets: [
            {
              name: "FriendActivity",
              label: "Playtivity",
              description: "See what your friends are listening to",
              minWidth: "220dp",
              minHeight: "150dp",
              targetCellWidth: 3,
              targetCellHeight: 2,
              maxResizeWidth: "700dp",
              maxResizeHeight: "700dp",
              resizeMode: "horizontal|vertical",
              updatePeriodMillis: 1800000,
            },
          ],
        },
      ],
      [
        "expo-build-properties",
        {
          android: {
            // R8 otherwise strips the generated Room database that WorkManager (used by the
            // widget library) creates by reflection, which crashed the app on launch.
            extraProguardRules: [
              "-keep class * extends androidx.room.RoomDatabase { *; }",
              "-keep class androidx.work.impl.WorkDatabase_Impl { *; }",
            ].join("\n"),
          },
        },
      ],
      "./plugins/withReleaseSigning",
    ],
    experiments: { typedRoutes: true },
    android: { package: "com.mliem.playtivity", versionCode: Number(build) || 1 },
    ios: { bundleIdentifier: "com.mliem.playtivity" },
  },
};
