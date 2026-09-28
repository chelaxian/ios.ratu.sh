import AppKit
// Original vector icon. Rendered during packaging, no external assets or services.
func icon(_ size: Int, _ file: String) throws {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let s=CGFloat(size), rect=NSRect(x:0,y:0,width:s,height:s)
    let background=NSBezierPath(roundedRect:rect,xRadius:s*0.22,yRadius:s*0.22)
    NSGradient(starting:NSColor.systemBlue,ending:NSColor.systemTeal)!.draw(in:background,angle:45)
    NSColor.white.setStroke()
    let p=NSBezierPath();p.lineWidth=s*0.075;p.lineCapStyle = .round;p.lineJoinStyle = .round
    p.move(to:NSPoint(x:s*0.5,y:s*0.20));p.line(to:NSPoint(x:s*0.5,y:s*0.48))
    p.line(to:NSPoint(x:s*0.25,y:s*0.72));p.move(to:NSPoint(x:s*0.5,y:s*0.48));p.line(to:NSPoint(x:s*0.75,y:s*0.72))
    p.move(to:NSPoint(x:s*0.25,y:s*0.55));p.line(to:NSPoint(x:s*0.25,y:s*0.72));p.line(to:NSPoint(x:s*0.42,y:s*0.72))
    p.move(to:NSPoint(x:s*0.58,y:s*0.72));p.line(to:NSPoint(x:s*0.75,y:s*0.72));p.line(to:NSPoint(x:s*0.75,y:s*0.55));p.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:file))
}
try icon(29,"Resources/icon.png")
try icon(58,"Resources/icon@2x.png")
try icon(87,"Resources/icon@3x.png")
try icon(128,"package-icon.png")
