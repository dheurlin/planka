import type { ElmInstance } from 'Types.elm';

export class ResizeObserverElmIntegration {
  private readonly pendingIdsToObserve: Set<string> = new Set();

  private readonly mutationObserver = new MutationObserver((rec) => {
    const allAddedChildren = rec.flatMap((mutation) => {
      const addedNodes: Array<Element> = [];

      for (const node of mutation.addedNodes) {
        if (!(node instanceof Element)) {
          continue;
        }
        addedNodes.push(node);
        addedNodes.push(...node.getElementsByTagName("*"));
      }

      return addedNodes;
    });

    for (const addedChild of allAddedChildren) {
      if (this.pendingIdsToObserve.has(addedChild.id)) {
        console.debug("Observing child:", addedChild.id);
        this.resizeObserver.observe(addedChild);
        this.pendingIdsToObserve.delete(addedChild.id);
      }
    }
  });

  private readonly resizeObserver = new ResizeObserver((rez) => {
    for (const elem of rez) {
      this.elmInstance.ports.resizeEventOccured?.send({
        elementId: elem.target.id,
        newWidth: elem.contentRect.width,
        newHeight: elem.contentRect.height,
      });
    }
  });

  constructor(private readonly elmInstance: ElmInstance) {
    this.mutationObserver.observe(document.body, {
      subtree: true,
      childList: true,
    });

    elmInstance.ports.observeElement?.subscribe((elementId) => {
      const maybeAlreadyExisting = document.getElementById(elementId);
      if (maybeAlreadyExisting != null) {
        console.debug(`Element with id ${elementId} was already in the DOM, observing straight away`);
        this.resizeObserver.observe(maybeAlreadyExisting);
      } else {
        this.pendingIdsToObserve.add(elementId);
      }
    });
  }
}
