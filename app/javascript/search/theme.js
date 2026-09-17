import { createTheme } from "@mui/material/styles";

const theme = createTheme({
  palette: {
    primary: { main: "#36563d" },
    background: { default: "#f5f2eb", paper: "#fffefa" },
    text: { primary: "#292e28", secondary: "#697064" },
    divider: "#d8dbcf",
    error: { main: "#914c32" },
  },
  typography: {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    button: { textTransform: "none" },
    h1: {
      fontFamily: 'Georgia, "Times New Roman", serif',
      fontWeight: 400,
      fontSize: "clamp(30px, 4vw, 42px)",
      lineHeight: 1.15,
      letterSpacing: "-.045em",
    },
  },
  shape: { borderRadius: 7 },
  motion: { reducedMotion: "system" },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        "@media (prefers-reduced-motion: reduce)": {
          ".MuiCircularProgress-root, .MuiCircularProgress-circle": {
            animation: "none !important",
          },
        },
      },
    },
  },
});

export default theme;
