const { withAppBuildGradle, withGradleProperties } = require("expo/config-plugins");

// The default 2 GiB heap and 512 MiB metaspace run out during the React Native release build.
const withGradleMemory = (config) =>
  withGradleProperties(config, (cfg) => {
    const props = cfg.modResults.filter((p) => !(p.type === "property" && p.key === "org.gradle.jvmargs"));
    props.push({ type: "property", key: "org.gradle.jvmargs", value: "-Xmx4096m -XX:MaxMetaspaceSize=1024m" });
    cfg.modResults = props;
    return cfg;
  });

// Signs release builds with the keystore the scripts export, so updates install over earlier APKs.
module.exports = (config) =>
  withAppBuildGradle(withGradleMemory(config), (cfg) => {
    const gradle = cfg.modResults.contents;
    if (gradle.includes("ANDROID_KEYSTORE_PATH")) return cfg;
    const signing = `
        release {
            if (System.getenv("ANDROID_KEYSTORE_PATH")) {
                storeFile file(System.getenv("ANDROID_KEYSTORE_PATH"))
                storePassword System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias System.getenv("ANDROID_KEY_ALIAS")
                keyPassword System.getenv("ANDROID_KEY_PASSWORD")
            }
        }`;
    cfg.modResults.contents = gradle
      .replace(/(signingConfigs\s*\{[\s\S]*?debug\s*\{[\s\S]*?\n\s*\})/, `$1${signing}`)
      .replace(/(buildTypes\s*\{[\s\S]*?release\s*\{[\s\S]*?)signingConfig signingConfigs\.debug/, `$1signingConfig System.getenv("ANDROID_KEYSTORE_PATH") ? signingConfigs.release : signingConfigs.debug`);
    return cfg;
  });
