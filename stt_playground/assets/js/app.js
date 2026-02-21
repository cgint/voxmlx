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
import topbar from "../vendor/topbar"

const SAMPLING_RATE = 16000

const hooks = {
  MicStreamer: {
    mounted() {
      this.mediaStream = null
      this.audioCtx = null
      this.sourceNode = null
      this.workletNode = null
      this.workletUrl = null

      this.el.addEventListener("click", () => {
        if (this.el.dataset.recording === "true") {
          this.stopRecording()
        } else {
          this.startRecording()
        }
      })
    },

    updated() {},

    async startRecording() {
      try {
        if (!window.AudioWorkletNode) {
          throw new Error("AudioWorklet is not supported in this browser")
        }

        this.mediaStream = await navigator.mediaDevices.getUserMedia({audio: true})
        this.audioCtx = new AudioContext()
        this.sourceNode = this.audioCtx.createMediaStreamSource(this.mediaStream)

        this.workletUrl = this.createWorkletModuleUrl()
        await this.audioCtx.audioWorklet.addModule(this.workletUrl)

        this.workletNode = new AudioWorkletNode(this.audioCtx, "stt-mic-processor", {
          numberOfInputs: 1,
          numberOfOutputs: 1,
          channelCount: 1,
          processorOptions: {targetSampleRate: SAMPLING_RATE, chunkSize: 2048}
        })

        this.workletNode.port.onmessage = ({data}) => {
          const raw = new Uint8Array(data)
          const converted = this.convertEndianness32(
            raw,
            this.getEndianness(),
            this.el.dataset.endianness
          )

          const b64 = this.uint8ToBase64(converted)
          try {
            this.pushEvent("audio_chunk", {pcm_b64: b64})
          } catch (_e) {}
        }

        this.sourceNode.connect(this.workletNode)
        this.workletNode.connect(this.audioCtx.destination)

        this.pushEvent("start_stream", {})
      } catch (error) {
        await this.cleanupAudioGraph()

        try {
          this.pushEvent("audio_error", {message: error.message || "Failed to start microphone"})
        } catch (_e) {}
      }
    },

    async stopRecording() {
      try {
        await this.cleanupAudioGraph()
      } finally {
        try {
          this.pushEvent("stop_stream", {})
        } catch (_e) {}
      }
    },

    async cleanupAudioGraph() {
      if (this.workletNode) {
        this.workletNode.port.onmessage = null
        this.workletNode.disconnect()
      }

      if (this.sourceNode) this.sourceNode.disconnect()
      if (this.mediaStream) this.mediaStream.getTracks().forEach((t) => t.stop())
      if (this.audioCtx) await this.audioCtx.close()

      if (this.workletUrl) {
        URL.revokeObjectURL(this.workletUrl)
      }

      this.workletNode = null
      this.sourceNode = null
      this.mediaStream = null
      this.audioCtx = null
      this.workletUrl = null
    },

    createWorkletModuleUrl() {
      const workletSource = `
        class SttMicProcessor extends AudioWorkletProcessor {
          constructor(options) {
            super()
            this.targetSampleRate = options.processorOptions.targetSampleRate
            this.chunkSize = options.processorOptions.chunkSize || 2048
            this.inputSampleRate = sampleRate
            this.pending = []
          }

          downsample(input) {
            if (this.targetSampleRate >= this.inputSampleRate) {
              return new Float32Array(input)
            }

            const ratio = this.inputSampleRate / this.targetSampleRate
            const newLength = Math.round(input.length / ratio)
            const result = new Float32Array(newLength)

            let offsetResult = 0
            let offsetInput = 0

            while (offsetResult < result.length) {
              const nextOffsetInput = Math.round((offsetResult + 1) * ratio)
              let accum = 0
              let count = 0

              for (let i = offsetInput; i < nextOffsetInput && i < input.length; i++) {
                accum += input[i]
                count++
              }

              result[offsetResult] = count > 0 ? accum / count : 0
              offsetResult++
              offsetInput = nextOffsetInput
            }

            return result
          }

          appendAndEmit(samples) {
            for (let i = 0; i < samples.length; i++) {
              this.pending.push(samples[i])
            }

            while (this.pending.length >= this.chunkSize) {
              const chunk = this.pending.splice(0, this.chunkSize)
              const output = new Float32Array(chunk)
              this.port.postMessage(output.buffer, [output.buffer])
            }
          }

          process(inputs) {
            const input = inputs[0]
            if (!input || !input[0] || input[0].length === 0) {
              return true
            }

            const downsampled = this.downsample(input[0])
            if (downsampled.length > 0) {
              this.appendAndEmit(downsampled)
            }

            return true
          }
        }

        registerProcessor("stt-mic-processor", SttMicProcessor)
      `

      return URL.createObjectURL(new Blob([workletSource], {type: "application/javascript"}))
    },

    convertEndianness32(uint8, from, to) {
      if (from === to) return uint8
      for (let i = 0; i < uint8.byteLength; i += 4) {
        const b1 = uint8[i]
        const b2 = uint8[i + 1]
        const b3 = uint8[i + 2]
        const b4 = uint8[i + 3]
        uint8[i] = b4
        uint8[i + 1] = b3
        uint8[i + 2] = b2
        uint8[i + 3] = b1
      }
      return uint8
    },

    getEndianness() {
      const buffer = new ArrayBuffer(2)
      const int16Array = new Uint16Array(buffer)
      const int8Array = new Uint8Array(buffer)
      int16Array[0] = 1
      return int8Array[0] === 1 ? "little" : "big"
    },

    uint8ToBase64(bytes) {
      let binary = ""
      const chunkSize = 0x8000
      for (let i = 0; i < bytes.length; i += chunkSize) {
        const chunk = bytes.subarray(i, i + chunkSize)
        binary += String.fromCharCode.apply(null, chunk)
      }
      return btoa(binary)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

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
    window.addEventListener("keyup", e => keyDown = null)
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
