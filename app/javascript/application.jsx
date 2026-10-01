import { createRoot } from "react-dom/client";
import { CssBaseline, ThemeProvider } from "@mui/material";
import SearchApp from "./search/SearchApp";
import theme from "./search/theme";

const container = document.getElementById("search-root");
if (container) {
  createRoot(container).render(
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <SearchApp />
    </ThemeProvider>,
  );
}
