// Injected only into a private offscreen copy of the real UI by media-capture.py.
        TestCase { id: demoInput; name: "ReleaseMedia"; when: false }
        property bool mediaBusy: false
        property int mediaFrame: 0
        property real pointerX: 1120
        property real pointerY: 720
        property real pointerPulse: 0
        property bool showPointer: true
        Canvas {
            id: demoPointer; parent: window.contentItem; z: 10000
            x: window.pointerX; y: window.pointerY; width: 32; height: 38
            visible: window.showPointer
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
            onPaint: {
                var c=getContext("2d"); c.clearRect(0,0,width,height)
                c.beginPath(); c.moveTo(2,2); c.lineTo(2,25); c.lineTo(8,20)
                c.lineTo(13,31); c.lineTo(17,29); c.lineTo(12,18); c.lineTo(21,18); c.closePath()
                c.fillStyle="#ffffff"; c.fill(); c.strokeStyle="#253D36"; c.lineWidth=1.5; c.stroke()
            }
        }
        Timer {
            interval: 50; running: true; repeat: true
            property int stalls: 0
            property var dragOrigin: null
            function check(ok, why) { if(!ok) throw new Error(why) }
            function editor(i) {
                var loader=annotationRepeater.itemForAnnotation(i)
                return loader ? loader.item : null
            }
            function point(item,x,y) {
                var p=item.mapToItem(window.contentItem,x,y); window.pointerX=p.x; window.pointerY=p.y
            }
            function click(item,x,y) {
                check(window.interactionReady && !window.modalActive, "Click blocked by app state")
                if(x===undefined)x=item.width/2
                if(y===undefined)y=item.height/2
                point(item,x,y); demoInput.mouseMove(item,x,y); demoInput.mouseClick(item,x,y)
            }
            function letter(field, before, char) {
                check(field && field.activeFocus && field.text===before,"Typing target/focus/value changed")
                var modifier=/[A-Z]/.test(char)?Qt.ShiftModifier:Qt.NoModifier
                demoInput.keyClick(char,modifier)
                check(field.text===before+char,"Typed character was not confirmed: "+JSON.stringify({actual:field.text,wanted:before+char}))
            }
            function spell(start, value, field, f) {
                if(f>=start && f<start+value.length*2 && (f-start)%2===0) {
                    var i=(f-start)/2; letter(field,value.slice(0,i),value[i])
                }
            }
            onTriggered: {
                if(window.mediaBusy)return
                window.mediaBusy=true
                try {
                    if(!window.interactionReady || window.restoringView || window.busy || renderedPage.status!==Image.Ready) {
                        if(++stalls>300)throw new Error("Timed out waiting for ready page")
                        window.mediaBusy=false; return
                    }
                    stalls=0
                    var f=window.mediaFrame
                    if(f===0) {
                        check(pages.count===3,"Unexpected sample")
                        window.width=1280; window.height=860; window.zoom=0.60
                        window.preferredTextSize=18; window.preferredTextColor="#253d36"
                        Theme.load(PALETTES[0]); window.positionReadingPage(0,false)
                    }
                    if(f===36) { point(viewport,viewport.width*.7,viewport.height*.7); continuousWheel.handleWheel({pixelDelta:Qt.point(0,0),angleDelta:Qt.point(0,0),phase:Qt.ScrollBegin},Date.now()) }
                    if(f>=38 && f<=48) continuousWheel.handleWheel({pixelDelta:Qt.point(0,-6),angleDelta:Qt.point(0,0),phase:Qt.ScrollUpdate},Date.now())
                    if(f===49) continuousWheel.handleWheel({pixelDelta:Qt.point(0,0),angleDelta:Qt.point(0,0),phase:Qt.ScrollEnd},Date.now())
                    if(f===76) { continuousWheel.stop(); demoInput.keyClick(Qt.Key_F,Qt.ControlModifier) }
                    spell(82,"Sunday",findBar.field,f)
                    if(f===119) check(searchController.results.length>0 && window.currentIndex===1,"Search did not find the itinerary")
                    if(f===135) { demoInput.keyClick(Qt.Key_Escape); paper.forceActiveFocus(); demoInput.keyClick(Qt.Key_B,Qt.ControlModifier) }
                    if(f===150) { demoInput.keyClick(Qt.Key_End,Qt.ControlModifier); window.positionReadingPage(2,false) }
                    if(f===175) click(textButton)
                    if(f===183) click(paper,paper.width*.09,paper.height*.331)
                    spell(190,"Alex Morgan",editor(0),f)
                    if(f===216) { check(annotations.get(0).value==="Alex Morgan","Name missing"); demoInput.keyClick(Qt.Key_Return) }
                    if(f===230) click(textButton)
                    if(f===238) click(paper,paper.width*.09,paper.height*.495)
                    spell(245,"Window seat, please.",editor(1),f)
                    if(f===287) { check(annotations.get(1).value==="Window seat, please.","Note missing"); demoInput.keyClick(Qt.Key_Return) }
                    if(f===289) {
                        var h=editor(1).resizeHandle; check(h.visible,"Resize handle missing")
                        dragOrigin=h.mapToItem(paper,5,8); point(h,5,8);demoInput.mousePress(h,5,8)
                    }
                    if(f>=290 && f<=300) {
                        point(paper,dragOrigin.x+(f-289)*10,dragOrigin.y)
                        demoInput.mouseMove(paper,dragOrigin.x+(f-289)*10,dragOrigin.y)
                    }
                    if(f===301) {
                        demoInput.mouseRelease(paper,dragOrigin.x+110,dragOrigin.y)
                        check(annotations.get(1).nw>0.35,"Field did not resize")
                    }
                    if(f===307) { var e=editor(0); point(e,15,10); demoInput.mouseDoubleClickSequence(e,15,10) }
                    if(f===313) { check(editor(0).activeFocus,"Correction field not focused"); demoInput.keyClick(Qt.Key_A,Qt.ControlModifier); demoInput.keyClick(Qt.Key_Backspace) }
                    spell(317,"Alex Rivera",editor(0),f)
                    if(f===342) { check(annotations.get(0).value==="Alex Rivera","Correction missing"); demoInput.keyClick(Qt.Key_Return) }
                    if(f===344) { demoInput.mouseMove(viewport,viewport.width-50,viewport.height-50); point(viewport,viewport.width-50,viewport.height-50) }
                    if(f===351) { demoInput.keyClick(Qt.Key_Right,Qt.ShiftModifier); demoInput.keyClick(Qt.Key_Right,Qt.ShiftModifier) }
                    if(f===364) demoInput.keyClick(Qt.Key_Z,Qt.ControlModifier)
                    if(f===380) {
                        window.clearCanvasSelection(); window.pointerX=1140;window.pointerY=700
                        demoInput.mouseMove(viewport,viewport.width-50,viewport.height-50)
                        // Omit this status-message settling pause from the edited film.
                        demoInput.wait(4600)
                    }
                    if(f===410) Theme.load(PALETTES[1])
                    if(f===455) Theme.load(PALETTES[2])
                    if(f===500) { Theme.load(PALETTES[0]); click(editor(1),15,10) }
                    if(f===502) { demoInput.mouseMove(viewport,viewport.width-50,viewport.height-50); point(viewport,viewport.width-50,viewport.height-50) }
                    if(f===530) { window.clearCanvasSelection(); point(saveButton,saveButton.width/2,saveButton.height/2); window.saveTo(EXPORT) }
                    if(f===560) check(!window.statusError && !window.busy && window.draftPersisted,"Export/draft was not acknowledged")
                    if(f===595) { console.log("MEDIA_PASS "+JSON.stringify({frames:f,marks:window.annotationPayload(),pages:pages.count})); Qt.quit(); return }
                    var shots={26:"01-reading-tokyo-night",123:"02-find-tokyo-night",140:"03-bookmarked",399:"04-editing-tokyo-night",439:"05-editing-latte",484:"06-editing-gruvbox",518:"07-editing-controls",581:"08-exported"}
                    var shot=shots[f]
                    if(shot)window.showPointer=false
                    window.contentItem.grabToImage(function(result) {
                        try {
                            check(result.saveToFile(OUTPUT+"/frames/"+String(f).padStart(5,"0")+".png"),"Frame capture failed")
                            if(shot)check(result.saveToFile(OUTPUT+"/"+shot+".png"),"Screenshot failed")
                            window.showPointer=true; window.mediaFrame++; window.mediaBusy=false
                        } catch(error) { console.error("Error: "+error);Qt.quit() }
                    })
                } catch(error) { console.error("Error: media frame "+window.mediaFrame+": "+error);Qt.quit() }
            }
        }
