# Quick Camera +QR

This is a fork from [ Quick Camera ](https://github.com/simonguest/quick-camera). Thanks to the author for making such an efficient, reliable camera utility.  
We plan to add QR code reading functionality by utilizing [ Zbar ](https://github.com/mchehab/zbar?utm_source=chatgpt.com) as the backend.

## Motivation

It seems like currently there's no FOSS lightweight QR code reader for macOS. I use QR codes day-to-day for sending Wi-Fi passwords, web links, draft sentences, etc., since they're minimal and just work.  
I've been using Quick Camera because it's lightweight and reliable. In addition, it's a saintly FOSS. One thing that I'd been missing for the software is just the QR code reading functionality.  
For a while, I was just hoping someone would add it. But wait... I'm a programmer too. And I realized my cousin can build apps for macOS. So why don't we build it ourselves?

## Objective

Our objective for this app development is pretty simple. **Just adding QR code reading functionality to the upstream**.
Keeping it simple, separation of concerns.  
Optimally, bringing the same lightweight and efficient experience as the upstream provides.
