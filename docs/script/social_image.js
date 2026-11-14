// Renders public/social.png, the picture link previews show (og:image): the name and the tagline on
// wada red, styled like the landing page's closing section. Rerun after changing those:
//
//   RAILS_ENV=production bin/rails kiln:build && node script/social_image.js
//
// It uses the Playwright from the gem's own node_modules, and serves dist/ itself.

const { createServer } = require("node:http")
const { readFile } = require("node:fs/promises")
const path = require("node:path")
const { chromium } = require(path.join(__dirname, "../../node_modules/playwright"))

const DIST = path.join(__dirname, "../dist")
const OUT = path.join(__dirname, "../public/social.png")
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".json": "application/json" }

const server = createServer(async (request, response) => {
  let file = path.join(DIST, decodeURIComponent(new URL(request.url, "http://x").pathname))
  if (file.endsWith("/")) file += "index.html"
  try {
    const body = await readFile(file)
    response.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" }).end(body)
  } catch {
    response.writeHead(404).end()
  }
})

server.listen(0, "127.0.0.1", async () => {
  const browser = await chromium.launch()
  try {
    // 1200x630 is the size previews expect; twice the pixels keeps the text sharp.
    const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2 })
    await page.goto(`http://127.0.0.1:${server.address().port}/`, { waitUntil: "networkidle" })
    await page.evaluate(() => document.fonts.ready)
    // The overlay loads after the page, so a rule hides it whenever it arrives.
    await page.addStyleTag({ content: "tensaku-overlay { display: none !important; }" })
    // The card replaces the page, in the style of its closing section: wada red, white type and the
    // hanamaru, large and faint, running off the right edge. The page's stylesheets give the fonts and
    // colors.
    await page.evaluate(() => {
      const mark = document.querySelector(".cta__mark").src
      const logo = document.querySelector('header a[aria-label="Tensaku home"] img').src
      const heading = getComputedStyle(document.querySelector(".hero__title")).fontFamily
      document.body.innerHTML = `
        <div class="social-card">
          <img class="social-card__mark" src="${mark}" alt="">
          <div class="social-card__brand"><img src="${logo}" alt="">tensaku</div>
          <p class="social-card__line">Fix your Rails app in the browser.</p>
        </div>`
      const style = document.createElement("style")
      style.textContent = `
        body { margin: 0; background: var(--wada-red); }
        .social-card { position: relative; overflow: hidden; width: 100vw; height: 100vh; box-sizing: border-box;
          display: flex; flex-direction: column; justify-content: center; gap: 28px; padding: 0 96px;
          background: var(--wada-red); color: #fff; font-family: ${heading}; }
        .social-card__mark { position: absolute; top: -30%; right: 0; height: 160%; transform: translateX(30%);
          filter: brightness(0) invert(1); opacity: .15; }
        .social-card__brand { position: relative; display: flex; align-items: center; gap: 28px;
          font-size: 168px; font-weight: 700; line-height: 1; letter-spacing: -0.04em; }
        .social-card__brand img { width: 136px; height: 136px; filter: brightness(0) invert(1); }
        .social-card__line { position: relative; margin: 0; max-width: 820px; font-size: 56px; font-weight: 600;
          line-height: 1.1; letter-spacing: -0.02em; color: rgb(255 255 255 / .9); }`
      document.head.append(style)
    })
    await page.evaluate(() => Promise.all(Array.from(document.images, (image) => image.decode())))
    // Flex centers the line boxes, which hold room below the text's baseline, so the type looked low:
    // center what shows instead, from the top of the logo to the tagline's baseline.
    await page.evaluate(() => {
      const top = document.querySelector(".social-card__brand img").getBoundingClientRect().top
      const line = document.querySelector(".social-card__line")
      const marker = document.createElement("span")
      marker.style.cssText = "display: inline-block; width: 0; height: 0; vertical-align: baseline"
      line.append(marker)
      const baseline = marker.getBoundingClientRect().top
      const offset = innerHeight / 2 - (top + baseline) / 2
      document.querySelectorAll(".social-card__brand, .social-card__line").forEach((element) => { element.style.translate = `0 ${offset}px` })
    })
    await page.waitForTimeout(300)
    await page.screenshot({ path: OUT })
    console.log(`Wrote ${path.relative(process.cwd(), OUT)}`)
  } finally {
    await browser.close()
    server.close()
  }
})
