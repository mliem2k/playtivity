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
    icon: "./assets/icon/icon.png",
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
              minHeight: "110dp",
              targetCellWidth: 3,
              targetCellHeight: 2,
              maxResizeWidth: "700dp",
              maxResizeHeight: "700dp",
              resizeMode: "horizontal|vertical",
              previewImage: "./assets/widget/preview.png",
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
              // WorkManager runs the widget's headless task and instantiates its workers and input
              // mergers by reflection; shrunk, it fails and the widget never draws.
              "-keep class androidx.work.** { *; }",
              "-keep class com.reactnativeandroidwidget.** { *; }",
            ].join("\n"),
          },
        },
      ],
      "./plugins/withReleaseSigning",
    ],
    experiments: { typedRoutes: true },
    android: {
      package: "com.mliem.playtivity",
      permissions: ["REQUEST_INSTALL_PACKAGES"],
      versionCode: Number(build) || 1,
      adaptiveIcon: {
        foregroundImage: "./assets/icon/adaptive-foreground.png",
        monochromeImage: "./assets/icon/adaptive-monochrome.png",
        backgroundColor: "#000000",
      },
    },
    ios: { bundleIdentifier: "com.mliem.playtivity" },
  },
};
