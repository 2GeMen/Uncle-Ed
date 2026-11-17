# 机盖装饰贴图

生成方式：内置 image_gen（imagegen 技能），使用用户提供的合盖实物照片作造型参考。生成的是平面装饰纹理，不包含硬件或界面；运行时由原生绘制代码裁切至机盖并参与铰链动画。

最终文件：black-edition-lid.png。

最终提示词：

Use case: product-mockup. Asset type: flat UV texture artwork for the OUTSIDE LID of a native macOS virtual Nintendo DSi Pokemon Black limited edition.
Reference image 1 is a photo of the requested physical lid and is the visual reference ONLY. Generate a new FLAT ORTHOGRAPHIC front-facing lid-surface texture with NO perspective. Wide horizontal rectangle aspect 2:1. It must look like the dark charcoal matte plastic surface of the reference, with fine glossy BLACK engraved linework of Reshiram and Zekrom facing toward each other across the two halves. Reshiram on left with feathered wings and flowing tail, Zekrom on right with angular armored wings and turbine tail, intricate recognizable organic contours rather than geometric stick figures. Dark black-on-charcoal low contrast, tiny gray edge highlights on the engraved grooves, very fine subtle plastic grain. Fill almost the entire width with the dragons, leaving a narrow lower margin. No text, no logo lettering, no camera, no hinges, no screws, no outer device body border, no background table, no shadows outside the rectangle, no watermark. This is ONLY the flat artwork surface that code will clip into a rounded lid; hardware, camera and gold lettering are drawn separately in code. The pattern should stay visible but subtle, premium photographic material. Match reference motifs and restrained contrast; avoid bright outlines, avoid colorful illustrations. Produce a clean approximately 1600x800 rectangular texture.
