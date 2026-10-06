// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/logger_dashboard"
import topbar from "../vendor/topbar"
import Chart from "chart.js/auto"

window.Chart = Chart

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A file pushed by the server. The log viewer builds its export body from the
// rows it already holds, so there is no request to point an anchor at and no
// route to add: the browser turns the pushed body into a Blob and downloads it.
// Pushed events are dispatched on the window with a `phx:` prefix.
window.addEventListener("phx:logs-download", ({detail}) => {
  const url = URL.createObjectURL(new Blob([detail.body], {type: detail.content_type}))
  const link = document.createElement("a")

  // Firefox only honours a click on an anchor that is in the document.
  link.href = url
  link.download = detail.filename
  link.style.display = "none"
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)

  // Revoked on the next tick rather than immediately: the download has only
  // started at this point, and some browsers read the blob asynchronously.
  setTimeout(() => URL.revokeObjectURL(url), 0)
})

// A single log row pushed by the server for the clipboard. Mirrors the
// logs-download flow above, but writes text instead of a file. The body is the
// row's export line, so copy and export cannot disagree. On denial the row's
// expanded panel holds the same text, and a notice says so rather than failing
// silently.
window.addEventListener("phx:logs-copy", async ({detail}) => {
  const write = async () => {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(detail.body)
      return true
    }

    // Fallback for contexts without the async clipboard API.
    const area = document.createElement("textarea")
    area.value = detail.body
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()

    let ok = false
    try {
      ok = document.execCommand("copy")
    } catch {
      ok = false
    }
    document.body.removeChild(area)
    return ok
  }

  let ok = false
  try {
    ok = await write()
  } catch {
    ok = false
  }

  if (!ok) {
    const note = document.createElement("div")
    note.setAttribute("role", "alert")
    note.className = "alert alert-warning fixed bottom-4 right-4 z-50 w-auto shadow-lg"
    note.textContent = "Could not copy to clipboard — expand the row to select the text manually."
    document.body.appendChild(note)
    setTimeout(() => note.remove(), 4000)
  }
})

// Column resize for the log viewer table. Widths live in CSS variables on
// #logs-table, so they survive LiveView stream re-inserts and are never sent
// to the server or written into the URL. The message column has no handle and
// flexes into whatever the fixed columns leave behind.
const logsResizeVars = {
  ts: "--logs-col-ts",
  level: "--logs-col-level",
  node: "--logs-col-node",
  source: "--logs-col-source"
}

document.addEventListener("mousedown", (e) => {
  const handle = e.target.closest("[data-resize]")
  if (!handle) return

  const table = handle.closest("#logs-table")
  const variable = logsResizeVars[handle.getAttribute("data-resize")]
  if (!table || !variable) return

  e.preventDefault()

  const startX = e.clientX
  const startWidth = handle.parentElement.getBoundingClientRect().width
  const minWidth = 48

  const onMove = (move) => {
    const width = Math.max(minWidth, startWidth + move.clientX - startX)
    table.style.setProperty(variable, `${width}px`)
  }
  const onUp = () => {
    document.removeEventListener("mousemove", onMove)
    document.removeEventListener("mouseup", onUp)
  }

  document.addEventListener("mousemove", onMove)
  document.addEventListener("mouseup", onUp)
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

