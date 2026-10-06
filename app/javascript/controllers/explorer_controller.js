import { Controller } from "@hotwired/stimulus"

// Map and timeline of a year of observations and night winds.
//
// The server sends two "cubes" once (see Analytics::ActivityCube and
// Analytics::WindCube). Everything after that happens here: scrubbing the
// timeline only re-sums a few small arrays and updates map feature states,
// with no request, which is what keeps it smooth.

// Colours of everything drawn on the map and chart, for the browser's light
// and dark settings. The ramp always runs from "blends into the basemap" to
// "stands out": yellow to purple on a pale map, purple to yellow on a dark one.
const VIRIDIS = ["#fde725", "#7ad151", "#22a884", "#2a788e", "#414487", "#440154"]
const THEMES = {
  light: {
    basemap: "https://tiles.openfreemap.org/styles/positron", background: "#eef1f4", ramp: VIRIDIS,
    fewRecords: "#9ca3af", ink: "#1f2937", paper: "#ffffff", bars: "#6b7280"
  },
  dark: {
    basemap: "https://tiles.openfreemap.org/styles/dark", background: "#0f172a", ramp: VIRIDIS.toReversed(),
    fewRecords: "#6b7280", ink: "#e5e7eb", paper: "#111827", bars: "#9ca3af"
  }
}
const DARK_QUERY = "(prefers-color-scheme: dark)"
// Width under which the legend's notes start folded, to leave the map visible.
const NARROW_QUERY = "(max-width: 639px)"
const BASEMAP_TIMEOUT_MS = 5000
// Below this many bird records a cell's share of a group means nothing.
const MIN_RECORDS = 5
// Zoom from which the finer hexagons (resolution 5) replace the coarse ones.
const FINE_ZOOM = 6.3
// Share of bird records at which a group's colour saturates.
const SHARE_SCALE = { warblers: 0.3, snow_goose: 0.1, raptors: 0.15 }
// Record count per day of window at which "all birds" saturates. The scale
// is logarithmic: a few cells near cities hold most of the records.
const COUNT_SCALE = 100
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const FRAME_MS = 110

export default class extends Controller {
  static targets = ["map", "group", "source", "window", "slider", "chart", "months", "date", "summary", "play",
                    "legendTitle", "legendRamp", "legendLow", "legendHigh", "legendNotes", "chartNote"]
  static values = { activityUrl: String, windUrl: String, sites: Array }

  connect() {
    this.group = "all"
    this.source = "inaturalist"
    this.windowDays = 7
    this.cubes = {}
    this.activeCells = new Set()
    // The map is drawn once with the theme found on arrival; if the
    // browser's setting changes, the page reloads to redraw it.
    this.darkQuery = window.matchMedia(DARK_QUERY)
    this.theme = THEMES[this.darkQuery.matches ? "dark" : "light"]
    this.themeChanged = () => window.location.reload()
    this.darkQuery.addEventListener("change", this.themeChanged)
    this.legendRampTarget.style.background = `linear-gradient(to right, ${this.theme.ramp.join(",")})`
    this.legendNotesTarget.open = !window.matchMedia(NARROW_QUERY).matches

    this.createMap()
  }

  async createMap() {
    const style = await this.basemapStyle()
    this.hasLabels = Boolean(style.glyphs)

    try {
      this.map = new maplibregl.Map({
        container: this.mapTarget, style, bounds: [-84.5, 41.5, -59.0, 51.5],
        fitBoundsOptions: { padding: 20 }, attributionControl: { compact: true }
      })
    } catch (error) {
      // No WebGL (old browser, or disabled by policy).
      this.legendTitleTarget.textContent = "The map needs WebGL, which this browser does not provide."
      return
    }
    this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right")
    this.map.on("error", (event) => console.error("map error:", event.error?.message || event))
    this.map.on("load", () => this.start())
  }

  // The basemap style, or a plain background when it does not answer in
  // time (some networks block it): the data still shows.
  async basemapStyle() {
    const plain = {
      version: 8, sources: {},
      layers: [{ id: "background", type: "background", paint: { "background-color": this.theme.background } }]
    }

    try {
      const response = await fetch(this.theme.basemap, { signal: AbortSignal.timeout(BASEMAP_TIMEOUT_MS) })
      return response.ok ? await response.json() : plain
    } catch (error) {
      return plain
    }
  }

  disconnect() {
    this.darkQuery.removeEventListener("change", this.themeChanged)
    this.stop()
    this.map?.remove()
  }

  async start() {
    this.addLayers()
    const [activity, wind] = await Promise.all([this.loadCube(4), fetch(this.windUrlValue).then((r) => r.json())])
    this.wind = wind
    this.day = activity.day_count - 1
    this.sliderTarget.max = this.day
    this.sliderTarget.value = this.day
    this.drawMonths(activity)
    this.useCube(4)
    this.map.on("zoomend", () => this.chooseResolution())
  }

  // --- data -----------------------------------------------------------------

  async loadCube(resolution) {
    if (!this.cubes[resolution]) {
      const response = await fetch(`${this.activityUrlValue}?resolution=${resolution}`)
      this.cubes[resolution] = await response.json()
    }
    return this.cubes[resolution]
  }

  async chooseResolution() {
    const resolution = this.map.getZoom() >= FINE_ZOOM ? 5 : 4
    if (resolution === this.resolution) return
    await this.loadCube(resolution)
    this.useCube(resolution)
  }

  useCube(resolution) {
    this.resolution = resolution
    this.cube = this.cubes[resolution]
    this.activeCells = new Set()
    this.map.getSource("cells").setData({
      type: "FeatureCollection",
      features: this.cube.cells.map((ring, id) => ({
        type: "Feature", id, properties: {}, geometry: { type: "Polygon", coordinates: [[...ring, ring[0]]] }
      }))
    })
    this.refresh()
  }

  // Positions, within one cell's block of a day array, of the counts to
  // read: [group counts, all-bird counts], for the chosen sources.
  seriesOffsets() {
    const sources = this.source === "both" ? ["inaturalist", "ebird"] : [this.source]
    const offset = (name) => this.cube.series.indexOf(name) + 1
    return {
      group: sources.map((source) => offset(`${source}:${this.group}`)),
      all: sources.map((source) => offset(`${source}:all`))
    }
  }

  // Sums the window ending on `day`: Map of cell id => [group, all].
  totals(day) {
    const { group, all } = this.seriesOffsets()
    const width = this.cube.series.length + 1
    const totals = new Map()

    for (let d = Math.max(0, day - this.windowDays + 1); d <= day; d++) {
      const values = this.cube.days[d]
      for (let i = 0; i < values.length; i += width) {
        const entry = totals.get(values[i]) || [0, 0]
        for (const o of group) entry[0] += values[i + o]
        for (const o of all) entry[1] += values[i + o]
        totals.set(values[i], entry)
      }
    }
    return totals
  }

  // 0..1 for the colour ramp, or null when there are too few records.
  intensity(groupCount, allCount) {
    if (this.group === "all") return Math.min(1, Math.log1p(allCount) / Math.log1p(COUNT_SCALE * this.windowDays))
    if (allCount < MIN_RECORDS) return null
    return Math.min(1, groupCount / allCount / SHARE_SCALE[this.group])
  }

  // --- drawing --------------------------------------------------------------

  addLayers() {
    const state = (name) => ["feature-state", name]
    this.map.addSource("cells", { type: "geojson", data: { type: "FeatureCollection", features: [] } })
    this.map.addLayer({
      id: "cells", type: "fill", source: "cells",
      paint: {
        // kind: 1 = too few records, 2 = coloured by value; absent = no records.
        "fill-color": ["case", ["==", state("kind"), 2],
          ["interpolate", ["linear"], ["coalesce", state("value"), 0],
            ...this.theme.ramp.flatMap((color, i) => [i / (this.theme.ramp.length - 1), color])],
          this.theme.fewRecords],
        "fill-opacity": ["case", ["==", state("kind"), 2], 0.72, ["==", state("kind"), 1], 0.35, 0],
        "fill-outline-color": "rgba(0,0,0,0)"
      }
    })

    this.map.addImage("wind-arrow", this.arrowImage(), { pixelRatio: 1.5 })
    this.map.addSource("wind", { type: "geojson", data: { type: "FeatureCollection", features: [] } })
    this.map.addLayer({
      id: "wind", type: "symbol", source: "wind",
      layout: {
        "icon-image": "wind-arrow", "icon-rotate": ["get", "bearing"], "icon-rotation-alignment": "map",
        "icon-size": ["interpolate", ["linear"], ["get", "speed"], 0, 0.45, 70, 1.3],
        "icon-allow-overlap": true
      },
      paint: { "icon-opacity": ["case", ["get", "forecast"], 0.45, 0.9] }
    })

    this.map.addSource("sites", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: this.sitesValue.map((site) => ({
          type: "Feature", properties: { name: site.name, description: site.description || "" },
          geometry: { type: "Point", coordinates: [site.longitude, site.latitude] }
        }))
      }
    })
    this.map.addLayer({
      id: "sites", type: "circle", source: "sites",
      paint: { "circle-radius": 5, "circle-color": this.theme.paper, "circle-stroke-color": this.theme.ink, "circle-stroke-width": 2 }
    })
    // Text needs the basemap's fonts.
    if (this.hasLabels) {
      this.map.addLayer({
        id: "site-labels", type: "symbol", source: "sites", minzoom: 5.5,
        layout: { "text-field": ["get", "name"], "text-size": 12, "text-offset": [0, 1.1], "text-anchor": "top", "text-font": ["Noto Sans Regular"] },
        paint: { "text-color": this.theme.ink, "text-halo-color": this.theme.paper, "text-halo-width": 1.5 }
      })
    }
    this.map.on("click", "sites", (event) => {
      const feature = event.features[0]
      new maplibregl.Popup({ closeButton: false })
        .setLngLat(feature.geometry.coordinates)
        .setHTML(`<strong>${this.escape(feature.properties.name)}</strong><br>${this.escape(feature.properties.description)}`)
        .addTo(this.map)
    })
    this.map.on("mouseenter", "sites", () => (this.map.getCanvas().style.cursor = "pointer"))
    this.map.on("mouseleave", "sites", () => (this.map.getCanvas().style.cursor = ""))
  }

  // Upward arrow; the layer rotates it to the wind's bearing.
  arrowImage() {
    const size = 48
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = size
    const context = canvas.getContext("2d")
    context.strokeStyle = context.fillStyle = this.theme.ink
    context.lineWidth = 4
    context.lineCap = "round"
    context.beginPath()
    context.moveTo(size / 2, size - 6)
    context.lineTo(size / 2, 14)
    context.stroke()
    context.beginPath()
    context.moveTo(size / 2, 3)
    context.lineTo(size / 2 - 9, 18)
    context.lineTo(size / 2 + 9, 18)
    context.closePath()
    context.fill()
    return context.getImageData(0, 0, size, size)
  }

  // Redraws everything that depends on the group, source or window.
  refresh() {
    this.drawChart()
    this.drawLegend()
    this.render()
  }

  // Redraws what depends on the current day only. Called on every frame
  // while scrubbing or playing.
  render() {
    const totals = this.totals(this.day)
    let records = 0
    let groupRecords = 0

    for (const id of this.activeCells) {
      if (!totals.has(id)) this.map.removeFeatureState({ source: "cells", id })
    }
    for (const [id, [groupCount, allCount]] of totals) {
      const value = this.intensity(groupCount, allCount)
      this.map.setFeatureState({ source: "cells", id }, value === null ? { kind: 1 } : { kind: 2, value })
      records += allCount
      groupRecords += groupCount
    }
    this.activeCells = new Set(totals.keys())

    this.renderWind()
    this.renderText(records, groupRecords)
  }

  // Wind of the night that ended on the morning of the current day.
  renderWind() {
    const night = this.wind.nights[this.day - 1] || []
    const forecast = Boolean(this.wind.forecast[this.day - 1])
    const features = []

    this.wind.points.forEach((coordinates, index) => {
      const u = night[index * 2]
      const v = night[index * 2 + 1]
      if (u === null || u === undefined) return
      features.push({
        type: "Feature", geometry: { type: "Point", coordinates },
        properties: { bearing: (Math.atan2(u, v) * 180) / Math.PI, speed: Math.hypot(u, v), forecast }
      })
    })
    this.map.getSource("wind").setData({ type: "FeatureCollection", features })
  }

  renderText(records, groupRecords) {
    const end = this.dateAt(this.day)
    const label = end.toLocaleDateString("en-CA", { year: "numeric", month: "long", day: "numeric", timeZone: "UTC" })
    this.dateTarget.textContent = this.windowDays === 1 ? label : `${this.windowDays} days ending ${label}`

    const count = records.toLocaleString("en-CA")
    if (this.group === "all") {
      this.summaryTarget.textContent = `${count} bird records`
    } else if (records < MIN_RECORDS) {
      this.summaryTarget.textContent = `${count} bird records: too few to tell`
    } else {
      const share = ((groupRecords / records) * 100).toFixed(1)
      this.summaryTarget.textContent = `${this.groupName()}: ${share}% of ${count} bird records`
    }
  }

  drawLegend() {
    if (this.group === "all") {
      this.legendTitleTarget.textContent = "Bird records per cell (logarithmic scale)"
      this.legendLowTarget.textContent = "1"
      this.legendHighTarget.textContent = `${COUNT_SCALE * this.windowDays}+`
    } else {
      this.legendTitleTarget.textContent = `${this.groupName()} as a share of all bird records in the cell`
      this.legendLowTarget.textContent = "0%"
      this.legendHighTarget.textContent = `${SHARE_SCALE[this.group] * 100}%+`
    }
  }

  // One bar per day for the whole region, and a strip for the night wind.
  drawChart() {
    const { group, all } = this.seriesOffsets()
    const width = this.cube.series.length + 1
    const days = this.cube.day_count
    const heights = new Array(days).fill(0)

    this.cube.days.forEach((values, day) => {
      let groupCount = 0
      let allCount = 0
      for (let i = 0; i < values.length; i += width) {
        for (const o of group) groupCount += values[i + o]
        for (const o of all) allCount += values[i + o]
      }
      heights[day] = this.group === "all" ? allCount : allCount >= MIN_RECORDS ? groupCount / allCount : 0
    })

    const max = Math.max(...heights, 0.0001)
    const bars = heights.map((height, day) => {
      const h = (height / max) * 50
      return `<rect x="${day}" y="${50 - h}" width="0.9" height="${h}" fill="${this.theme.bars}"/>`
    })
    const strip = this.tailwinds().map((tailwind, day) => {
      if (tailwind === null) return ""
      const strength = Math.min(1, Math.abs(tailwind) / 30)
      const color = tailwind >= 0 ? `rgba(22,163,74,${strength})` : `rgba(220,38,38,${strength})`
      return `<rect x="${day}" y="54" width="1" height="8" fill="${color}"/>`
    })

    this.chartTarget.setAttribute("viewBox", `0 0 ${days} 64`)
    this.chartTarget.innerHTML = bars.join("") + strip.join("")
    this.chartNoteTarget.textContent = this.group === "all"
      ? "bird records per day in the whole region."
      : `${this.groupName()} as a share of the day's bird records in the whole region.`
  }

  // Mean over the region of the wind's push along the seasonal direction of
  // travel, for the night ending on each day; null outside migration seasons.
  tailwinds() {
    return this.cube.days.map((_, day) => {
      const month = this.dateAt(day).getUTCMonth() + 1
      const heading = month >= 8 && month <= 11 ? 190 : month >= 3 && month <= 6 ? 10 : null
      const night = this.wind.nights[day - 1]
      if (heading === null || !night) return null

      const radians = (heading * Math.PI) / 180
      let sum = 0
      let count = 0
      for (let i = 0; i < night.length; i += 2) {
        if (night[i] === null || night[i] === undefined) continue
        sum += night[i] * Math.sin(radians) + night[i + 1] * Math.cos(radians)
        count++
      }
      return count ? sum / count : null
    })
  }

  // A label under the first day of each month.
  drawMonths(cube) {
    const labels = []
    for (let day = 0; day < cube.day_count; day++) {
      const date = this.dateAt(day, cube)
      if (date.getUTCDate() !== 1) continue
      const left = ((day / cube.day_count) * 100).toFixed(2)
      labels.push(`<span class="absolute border-l border-gray-300 pl-1 leading-none" style="left:${left}%">${MONTHS[date.getUTCMonth()]}</span>`)
    }
    this.monthsTarget.innerHTML = labels.join("")
  }

  // --- controls -------------------------------------------------------------

  chooseGroup(event) {
    this.group = event.currentTarget.dataset.group
    this.press(this.groupTargets, event.currentTarget)
    this.refresh()
  }

  chooseSource(event) {
    this.source = event.currentTarget.dataset.source
    this.press(this.sourceTargets, event.currentTarget)
    this.refresh()
  }

  chooseWindow(event) {
    this.windowDays = Number(event.currentTarget.dataset.window)
    this.press(this.windowTargets, event.currentTarget)
    this.refresh()
  }

  zoomTo(event) {
    this.map.fitBounds(JSON.parse(event.currentTarget.dataset.bounds), { padding: 20 })
  }

  // Points the map and timeline at what an answer is about.
  showAnswer(event) {
    const { bounds, date, group } = event.currentTarget.dataset
    const button = this.groupTargets.find((candidate) => candidate.dataset.group === group)
    if (button) {
      this.group = group
      this.press(this.groupTargets, button)
    }

    const day = Math.round((new Date(`${date}T00:00:00Z`) - this.dateAt(0)) / 86400000)
    this.day = Math.max(0, Math.min(this.cube.day_count - 1, day))
    this.sliderTarget.value = this.day
    this.map.fitBounds(JSON.parse(bounds), { padding: 60, maxZoom: 9 })
    this.refresh()
  }

  scrub() {
    this.day = Number(this.sliderTarget.value)
    if (this.cube) this.render()
  }

  togglePlay() {
    this.timer ? this.stop() : this.play()
  }

  play() {
    if (this.day >= this.cube.day_count - 1) this.day = 0
    this.showPlaying(true)
    this.timer = setInterval(() => {
      if (this.day >= this.cube.day_count - 1) return this.stop()
      this.day++
      this.sliderTarget.value = this.day
      requestAnimationFrame(() => this.render())
    }, FRAME_MS)
  }

  stop() {
    clearInterval(this.timer)
    this.timer = null
    if (this.hasPlayTarget) this.showPlaying(false)
  }

  // The play button draws a play or a pause icon from data-playing.
  showPlaying(playing) {
    this.playTarget.toggleAttribute("data-playing", playing)
    this.playTarget.ariaLabel = this.playTarget.title = playing ? "Pause" : "Play"
  }

  // --- helpers --------------------------------------------------------------

  press(buttons, pressed) {
    buttons.forEach((button) => button.setAttribute("aria-pressed", String(button === pressed)))
  }

  groupName() {
    return this.groupTargets.find((button) => button.dataset.group === this.group).textContent
  }

  dateAt(day, cube = this.cube) {
    const date = new Date(`${cube.first_day}T00:00:00Z`)
    date.setUTCDate(date.getUTCDate() + day)
    return date
  }

  escape(text) {
    const element = document.createElement("span")
    element.textContent = text
    return element.innerHTML
  }
}
