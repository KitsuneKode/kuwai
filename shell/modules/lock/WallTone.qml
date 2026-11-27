import QtQuick
import "../../services/lockPlate.mjs" as Plate

Canvas {
    id: probe
    property url source
    property var zones: []
    property var tones: []
    width: 32; height: 18
    opacity: 0
    renderStrategy: Canvas.Immediate
    property string held: ""
    function take() {
        const src = String(source);
        if (held && held !== src) unloadImage(held);
        held = src;
        if (!src) { tones = zones.map(() => 0); return; }
        if (isImageLoaded(src)) requestPaint(); else loadImage(src);
    }
    onImageLoaded: requestPaint()
    onPaint: {
        if (!held || !isImageLoaded(held)) return;
        const ctx = getContext("2d");
        ctx.drawImage(held, 0, 0, width, height);
        tones = zones.map(z => {
            const r = Plate.cells(z, width, height);
            return Plate.brightest(ctx.getImageData(r.x, r.y, r.width, r.height).data);
        });
    }
    onSourceChanged: take()
    onZonesChanged: if (held && isImageLoaded(held)) requestPaint()
    Component.onCompleted: take()
}
