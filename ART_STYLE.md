# Tensaku art style

Tensaku is a little pencil case for correcting the web.

Recognizable miniature tools, soft ink colors, the selected pen rising slightly,
translucent highlighter sweeps, and a handwritten check when a note is resolved.
The tooling feels like something you can pick up and use on the page. Let it be
whimsical wherever that makes an action clearer or more enjoyable.

This is the direction for the design pass after the core editing workflow is
usable. The examples below describe proposed behavior, not features already built.

## Primary UI reference

The selected annotation screenshot establishes the working overlay's structure:
a floating toolbar, area selection, and a nearby comment editor, with more
stationery character and Post-it notes for Tensaku.

Keep that compact structure: a small rounded toolbar with grouped actions, a
light translucent selection boundary, and a note editor beside the selected
element or area. Soft shadows lift the floating controls above the page. The
comment editor has one clear field and an obvious primary action. Give the
selection room to remain visible while the note is open.

Explore a dark, neutral toolbar that makes the ink colors and active tool easy
to recognize. Note cards can bring in warm Post-it yellow, muted pink, or mint,
with a small folded corner or a slightly lifted paper edge. A fresh note can
settle into place; a resolved note can receive a handwritten check. Keep editing
fields and text aligned even when a decorative corner or paper edge is irregular.

The pencil-case idea lives in the tool silhouettes, ink, note cards, and small
physical responses within this compact interface. A large illustrated desk or
worktable belongs in marketing artwork rather than taking over the working page.

## The pencil case

Give the tools the shapes and materials of real stationery. A fine pen has a
narrow nib. A marker has a broad tip. A highlighter has a chisel edge and a
translucent swatch. An eraser has exposed rubber and a paper sleeve.

Keep the illustrations in one family: consistent perspective, light source,
outline weight, and level of detail. Slightly softened edges and a little shading
give the tools volume. The tools can be more detailed than the surrounding controls.
Create original artwork rather than reproducing a stationery brand's packaging.

The active tool rises from the tray and shows its ink color. Hover can add a small
lift or tilt and reveal a label. Tool shape, position, and text all help identify
the selection. Keep labels, keyboard access, and clear focus states available.

The metaphor follows the action. A pen suggests a correction, a highlighter draws
attention, and an eraser removes a mark. Add a tool when its action exists.

## Ink, paper, and proofreading

Use warm paper tones for Tensaku's own surfaces, dark ink for text, and a small
set of soft accent colors. Explore correction red, pen blue, and muted yellow,
pink, or mint highlighter ink. The exact palette remains open until it is tested
on both light and dark pages.

Marks have a confident hand-drawn character: a curved underline, a slightly
irregular circle, a margin arrow, or a short handwritten check. Keep each mark's
geometry stable while it remains on screen. Random jitter on every redraw makes
the interface harder to follow.

Give each medium a distinct character. Pen lines are fine and opaque. Marker
strokes are broader. Highlighter strokes let the text show through and can have
slightly uneven ends. Correction marks and margin notes connect the visual style
to Tensaku's name, 添削.

Use paper texture sparingly on owned surfaces. Keep the host page's appearance
intact. Annotations must remain readable over photographs, saturated colors, and
dark backgrounds, with a clear focus indicator independent of the decorative ink.

## Lettering and layout

Keep working text, source locations, and editor content clear and easy to scan.
Use handwritten lettering for a few short labels, annotations, or brand moments.
[Shantell Sans](https://shantellsans.com/) is a candidate for marker-like accents.
Japanese text needs a companion font with an appropriate tone and full glyph coverage.

Carry the same materials and ink vocabulary through the toolbar, cursors, note
cards, help, and landing page. Clean alignment and generous space give the drawn
details room. Sketchy marks can emphasize content without making every panel edge
or line of text irregular.

## Motion follows the hand

Motion gives an action a physical response and then lets the interface settle.

| Action | Proposed response |
|---|---|
| Hover a tool | A small lift or tilt, with its name visible. |
| Select a tool | It rises from the tray and settles once. Its nib shows the selected color. |
| Add an underline or circle | The stroke draws along its path. |
| Highlight text | A translucent sweep crosses the selected text. |
| Erase a mark | A brief rubbing or wiping motion follows the removal. A few tiny crumbs are an optional accent. |
| Resolve a note | A handwritten check appears with a small settling motion. |
| Undo | The previous content and state return, with brief visual feedback. |

Let moments of delight come from the tools: a cap shifting, an eraser leaning
into a wipe, or a check finishing with a little flick. Keep frequent actions quick.
Avoid delays that make someone wait for an animation before continuing.

When reduced motion is requested, show the resulting state directly or use a
quiet color or opacity change. Success, errors, and the active tool must remain
understandable without animation or color alone.

## Animation tools and agent workflow

CSS transitions and keyframes are the default for hover, selection, and simple
reveals. Original SVG artwork keeps tool shapes and drawn marks editable as text.
The agent authors the artwork and animation; manual timeline editing is optional.

[Rough Notation](https://roughnotation.com/) and [Rough.js](https://roughjs.com/)
are the strongest library candidates for this style. Rough Notation handles
text-attached underlines, highlights, circles, and brackets. Rough.js generates
sketchy paths and shapes. Check their behavior inside Tensaku's overlay before adoption.

[Motion's JavaScript API](https://motion.dev/docs/animate) is an option when
interactive springs or coordinated sequences make CSS awkward. It works with
ordinary DOM and SVG elements and does not require React. A fixed spring curve
can also be [generated as CSS](https://motion.dev/docs/spring).

[Perfect Freehand](https://github.com/steveruizok/perfect-freehand) becomes relevant
if actual freehand input is added. Native SVG masks can handle an eraser wipe.

[Rive](https://rive.app/) is a later option for articulated characters or tools
with many connected animation states. Its [CLI](https://rive.app/docs/cli/overview)
can build scenes from text, render frames, and support an agent-driven workflow.
It adds an asset build and a playback runtime, so adopt it when the animation
benefits from those capabilities.

Parcela's current underline is a useful small example: an authored SVG path with
a CSS transition on `stroke-dashoffset`, in
`../parcela/docs/website/.vitepress/theme/PenMark.vue`. Its hero uses another custom
path. Rough Notation was saved as a reference but is not the library behind those marks.

## Landing page direction

Present Tensaku as a working correction tool. Lead with a small demonstration of
selecting text, making a correction, and leaving or resolving a note. Frame that
demonstration with the same pencil case used in the product.

Use drawn underlines to emphasize a few words, margin notes to explain the demo,
and arrows that point to real details. Let the hero have the most illustration.
Installation instructions, examples, and documentation keep a clear reading rhythm.

The page can reveal a stroke as it enters view or invite a visitor to try a safe
sample correction. Keep useful content visible before animation starts. Any
demonstration needs a readable still state for reduced motion and narrow screens.

Website references and the specific details worth borrowing live in the KaraKeep
collection **Projects → Tensaku — Stationery & Whimsy**, tagged `landing-page`.
These pages were reviewed in the browser on 2026-11-07. The borrowing suggestions
are our interpretation of their designs.

| Reference | What to borrow for Tensaku |
|---|---|
| [Excalidraw+](https://plus.excalidraw.com/) | The closest match for sketchy marks: a handwritten word in the headline, soft colored strokes, a pen nib, and an editor demonstration. |
| [Balsamiq](https://balsamiq.com/) | Surround clear product copy with drawn arrows, scribbles, and a comment bubble. Make the annotations part of explaining the tool. |
| [PencilBooth](https://www.pencilbooth.com/) | An illustrated creative workspace with paper, pencils, and tactile texture. A reference for an original stationery scene in the hero. |
| [Shantell Sans](https://shantellsans.com/) | Marker lettering as a whole visual language, including navigation and an invitation to interact. Use a smaller dose in Tensaku's working interface. |
| [Kinopio](https://kinopio.club/) | A product-led canvas with soft colored connections, paper texture, cards, and informal drawings. Useful for the demo's sense of direct manipulation. |
| [HEY](https://www.hey.com/) | Friendly lettering and hand-marked emphasis in a structured product page. A supporting reference for balancing personality with readable explanations. |

Start with Excalidraw+ for drawn marks, Balsamiq for annotated explanations, and
PencilBooth for the physical stationery atmosphere. Make Tensaku's pencil case
and correction workflow the original centerpiece.

## What makes the style work

The tools are recognizable at toolbar size, and their states remain clear while
someone works quickly. The same pen feels like the same pen in the toolbar, on
the page, and in the landing-page demo. Whimsy comes from small, deliberate details
that belong to correcting a draft.

Judge the result on real light and dark host pages, at narrow widths, with a
keyboard, and with reduced motion. The artwork and motion serve a usable editor.
