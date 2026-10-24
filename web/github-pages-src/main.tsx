import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import HandReviewApp from "../app/HandReviewApp";
import "../app/globals.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <HandReviewApp />
  </StrictMode>
);
