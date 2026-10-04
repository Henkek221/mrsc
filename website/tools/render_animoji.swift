import AppKit
import ObjectiveC

// Renders Apple's 3D Animoji stickers with the Mac's own AvatarKit (private framework, so it may break with a macOS update).
// swiftc -O website/tools/render_animoji.swift -o /tmp/render_animoji
// /tmp/render_animoji skull exploding_head skull.png      (1024 x 1024 PNG)
// /tmp/render_animoji boar face_with_symbols_over_mouth boar.png
// Sticker names live in /System/Library/PrivateFrameworks/AvatarKitContent.framework/Resources/stickers/animoji/<name>/
dlopen("/System/Library/PrivateFrameworks/AvatarKit.framework/AvatarKit", RTLD_NOW)
func cls(_ n: String) -> NSObject.Type { NSClassFromString(n) as! NSObject.Type }
func imp<T>(_ target: AnyObject, _ sel: String, _ type: T.Type) -> T {
    unsafeBitCast((target as! NSObject).method(for: NSSelectorFromString(sel))!, to: type)
}

let args = CommandLine.arguments
let name = args[1], sticker = args[2], out = args[3]
let points = Double(args.count > 4 ? args[4] : "512")!

let Animoji = cls("AVTAnimoji")
let avatar = Animoji.perform(NSSelectorFromString("animojiNamed:"), with: name)!.takeUnretainedValue()
let Config = cls("AVTStickerConfiguration")
let sel = NSSelectorFromString("stickerConfigurationForAnimojiNamed:inStickerPack:stickerName:")
let config = imp(Config, "stickerConfigurationForAnimojiNamed:inStickerPack:stickerName:", (@convention(c) (AnyObject, Selector, NSString, NSString, NSString) -> AnyObject?).self)(Config, sel, name as NSString, "stickers" as NSString, sticker as NSString)!

let Options = cls("AVTStickerGeneratorOptions")
let options = Options.perform(NSSelectorFromString("defaultOptions"))!.takeUnretainedValue()
imp(options, "setSize:", (@convention(c) (AnyObject, Selector, CGSize) -> Void).self)(options, NSSelectorFromString("setSize:"), CGSize(width: points, height: points))
imp(options, "setScaleFactor:", (@convention(c) (AnyObject, Selector, CGFloat) -> Void).self)(options, NSSelectorFromString("setScaleFactor:"), 2)

let gen = cls("AVTStickerGenerator").perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
_ = gen.perform(NSSelectorFromString("initWithAvatar:"), with: avatar)

var done = false
let handler: @convention(block) (AnyObject?) -> Void = { result in
    defer { done = true }
    guard let result else { print("no image"); return }
    print("got", type(of: result))
    var rep: NSBitmapImageRep?
    if let img = result as? NSImage, let tiff = img.tiffRepresentation { rep = NSBitmapImageRep(data: tiff) }
    else if CFGetTypeID(result) == CGImage.typeID { rep = NSBitmapImageRep(cgImage: result as! CGImage) }
    guard let png = rep?.representation(using: .png, properties: [:]) else { print("cannot encode"); return }
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote", out, rep!.pixelsWide, "x", rep!.pixelsHigh)
}
let gsel = NSSelectorFromString("stickerImageWithConfiguration:options:completionHandler:")
imp(gen, "stickerImageWithConfiguration:options:completionHandler:", (@convention(c) (AnyObject, Selector, AnyObject, AnyObject, Any) -> Void).self)(gen, gsel, config, options, handler)

let deadline = Date().addingTimeInterval(40)
while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
if !done { print("timed out") }
