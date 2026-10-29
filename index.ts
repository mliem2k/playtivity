import { registerWidgetTaskHandler } from "react-native-android-widget";
import { widgetTaskHandler } from "./src/widget/handler";

registerWidgetTaskHandler(widgetTaskHandler);

import "expo-router/entry";
