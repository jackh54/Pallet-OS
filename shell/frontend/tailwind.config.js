/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        chrome: {
          bg: "#202124",
          shelf: "#1f1f1f",
          surface: "#292a2d",
          accent: "#8ab4f8",
          text: "#e8eaed",
          muted: "#9aa0a6",
        },
      },
      boxShadow: {
        shelf: "0 -1px 0 rgba(255,255,255,0.08)",
      },
    },
  },
  plugins: [],
};
