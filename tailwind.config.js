/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}"],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: {
        bg: "#121212",
        raised: "#181818",
        elevated: "#282828",
        primary: "#1DB954",
        "primary-active": "#1ED760",
        muted: "#A7A7A7",
        subdued: "#535353",
        danger: "#E91429",
      },
    },
  },
};
