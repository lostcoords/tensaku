declare module "idiomorph" {
  interface Callbacks {
    beforeNodeMorphed?: (oldNode: Node, newNode: Node) => boolean | void
    beforeNodeRemoved?: (node: Node) => boolean | void
    beforeNodeAdded?: (node: Node) => boolean | void
  }

  interface Options {
    morphStyle?: "outerHTML" | "innerHTML"
    ignoreActiveValue?: boolean
    restoreFocus?: boolean
    callbacks?: Callbacks
  }

  export const Idiomorph: {
    morph(oldNode: Element, newContent: Element | string, options?: Options): unknown
  }
}
