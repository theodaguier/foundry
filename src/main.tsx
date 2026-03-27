import React from "react"
import ReactDOM from "react-dom/client"
import { TooltipProvider } from "@/components/ui/tooltip"
import App from "@/app"
import "@/styles/globals.css"
import { initAnalytics, trackAppOpened } from "@/lib/analytics"

initAnalytics()
trackAppOpened()

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <TooltipProvider>
      <App />
    </TooltipProvider>
  </React.StrictMode>
)
