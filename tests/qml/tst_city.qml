// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Window
import QtTest
import "../../package/contents/ui" as CityUi
import "../../package/contents/ui/code/city.js" as City
import "../../package/contents/ui/code/render.js" as Render
import "../../package/contents/ui/code/settings.js" as Settings

Item {
    id: host
    width: 1100; height: 700
    Component {
        id: fixtureComponent
        Item {
            id: fixture
            width: 1024; height: 72
            required property var journal
            required property var indexer
            property color topColor: "#183048"
            property color bottomColor: "#183048"
            property bool resources: true
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: fixture.topColor }
                    GradientStop { position: 1; color: fixture.bottomColor }
                }
            }
            Loader {
                id: tileLoader
                anchors.fill: parent
                active: fixture.resources
                sourceComponent: Component {
                    Item {
                        Repeater {
                            id: tileList
                            model: fixture.indexer.tileCount
                            delegate: CityUi.CanvasTile {
                                required property int index
                                x: index*512; width: 512; height: 72
                                renderer: fixture.indexer; tileIndex: index
                            }
                        }
                        function flush() {
                            fixture.indexer.flush(function(i,x,y,w,h) { tileList.itemAt(i).markDirty(Qt.rect(x,y,w,h)); });
                        }
                    }
                }
                function flush() { if (item) item.flush(); }
            }
            function flush() { tileLoader.flush(); }
        }
    }
    Component { id: viewComponent; CityUi.CityView { width: 800; height: 600 } }
    TestCase {
        name: "CityRasterAndScheduling"
        when: windowShown
        function makeJournal(count) {
            const e=City.createEngine({Seed:1,Scale:3,InitialBranches:1,EndMode:"hold"},200,12);
            const c=e.columns;
            e.segmentFrom[0]=85+5*c; e.segmentTo[0]=86+5*c;
            e.segmentFrom[1]=86+5*c; e.segmentTo[1]=86+6*c;
            e.segmentHue[0]=0; e.segmentHue[1]=120;
            e.segmentMain[0]=1; e.segmentMain[1]=1;
            e.segmentCity[0]=1; e.segmentCity[1]=1;
            e.segmentColor[0]=0; e.segmentColor[1]=1;
            e.segmentCount=count; e.journalCount=count;
            e.segmentActive.fill(1,0,count);
            return e;
        }
        function makeFixture(count,fill,gradient) {
            const e=makeJournal(count), s=Settings.defaults();
            s.FillCity=fill; s.FillOpacity=0.4;
            const r=Render.createRenderer(e,1024,72,host.Screen.devicePixelRatio,512);
            r.setStyle(s); r.reset();
            const f=createTemporaryObject(fixtureComponent,host,{journal:e,indexer:r,bottomColor:gradient ? "#684028" : "#183048"});
            verify(f !== null); wait(120); return {item:f, engine:e, indexer:r};
        }
        function test_qv4TypedArrays() {
            const e=City.createEngine({Seed:1},20,20);
            verify(e.occupancy instanceof Uint8Array);
            e.queueGenerations(1); verify(e.step(64)>0);
            verify(e.occupiedCount>0);
        }
        function test_tileSeam() {
            const scene=makeFixture(1,false,false), f=scene.item, image=grabImage(f);
            // Qt Quick Test's software grab keeps logical size but device-pixel coordinates.
            const factor=host.Screen.devicePixelRatio;
            for(let x=511;x<517;++x) verify(image.red(Math.floor(x*factor),Math.floor(31*factor))>100,"continuous stroke at "+x);
        }
        function test_paletteColors_data() {
            return [
                {tag:"aurora",palette:"aurora",color:"#66e3c4",main:true},
                {tag:"ember",palette:"ember",color:"#ff9e64",main:true},
                {tag:"monochrome",palette:"monochrome",color:"#c0caf5",main:true},
                {tag:"custom",palette:"custom",color:"#123abc",main:true},
                {tag:"original-offshoot",palette:"original",color:"#780000",main:false}
            ];
        }
        function test_paletteColors(data) {
            const e=makeJournal(1), s=Settings.defaults();
            e.segmentMain[0]=data.main ? 1 : 0;
            s.Palette=data.palette; s.CustomColors='["#123abc","#ef9123"]'; s.FillCity=true; s.FillOpacity=0.4;
            const r=Render.createRenderer(e,1024,72,host.Screen.devicePixelRatio,512);
            r.setStyle(s); r.reset();
            const f=createTemporaryObject(fixtureComponent,host,{journal:e,indexer:r});
            wait(120);
            const image=grabImage(f), factor=host.Screen.devicePixelRatio;
            const x=Math.floor(514*factor), y=Math.floor(31*factor);
            verify(Math.abs(image.red(x,y)-parseInt(data.color.slice(1,3),16))<=2,"stroke red matches selected palette");
            verify(Math.abs(image.green(x,y)-parseInt(data.color.slice(3,5),16))<=2,"stroke green matches selected palette");
            verify(Math.abs(image.blue(x,y)-parseInt(data.color.slice(5,7),16))<=2,"stroke blue matches selected palette");
            const fillY=Math.floor(34*factor);
            verify(Math.abs(image.red(x,fillY)-(parseInt(data.color.slice(1,3),16)*0.4+24*0.6))<=2,"fill red blends with background");
            verify(Math.abs(image.green(x,fillY)-(parseInt(data.color.slice(3,5),16)*0.4+48*0.6))<=2,"fill green blends with background");
            verify(Math.abs(image.blue(x,fillY)-(parseInt(data.color.slice(5,7),16)*0.4+72*0.6))<=2,"fill blue blends with background");
        }
        function test_undoToBackground_data() { return [{tag:"solid",gradient:false},{tag:"gradient",gradient:true}]; }
        function test_undoToBackground(data) {
            const empty=makeFixture(0,true,data.gradient), reference=grabImage(empty.item);
            empty.item.destroy(); wait(10);
            const scene=makeFixture(1,true,data.gradient), f=scene.item, painted=grabImage(f);
            verify(!painted.equals(reference));
            scene.engine.segmentCount=0; scene.engine.segmentActive[0]=0;
            scene.engine.changeIds[0]=-1; scene.engine.changeCount=1;
            scene.indexer.sync(); f.flush(); wait(120);
            verify(grabImage(f).equals(reference),"transparent undo restores underlying background exactly");
        }
        function test_overlapUndoMatchesFreshPrefix() {
            const scene=makeFixture(2,true,true), f=scene.item;
            const full=grabImage(f);
            scene.engine.segmentCount=1; scene.engine.segmentActive[1]=0;
            scene.engine.changeIds[0]=-2; scene.engine.changeCount=1;
            scene.indexer.sync(); f.flush(); wait(120);
            const undone=grabImage(f); verify(!full.equals(undone));
            f.destroy(); wait(10);
            const fresh=makeFixture(1,true,true);
            verify(undone.equals(grabImage(fresh.item)),"overlapping alpha fill survives replay in journal order");
        }
        function test_reverseEveryFrameMatchesSurvivingGeometry_data() {
            return [{tag:"filled",fill:true,width:2},{tag:"thin",fill:true,width:1.5},{tag:"strokes",fill:false,width:8}];
        }
        function test_reverseEveryFrameMatchesSurvivingGeometry(data) {
            const e=City.createEngine({Seed:73,Scale:3,InitialBranches:10},170,12);
            let guard=0;
            while(e.phase==="growing" && guard++<2000) {
                e.queueGenerations(200); e.step(4096);
            }
            compare(e.phase,"holding"); verify(e.segmentCount>500);
            const s=Settings.defaults(); s.FillCity=data.fill; s.LineWidth=data.width; s.FillOpacity=0.4;
            const incremental=Render.createRenderer(e,1024,72,host.Screen.devicePixelRatio,512);
            const reference=Render.createRenderer(e,1024,72,host.Screen.devicePixelRatio,512);
            incremental.setStyle(s); incremental.reset(); reference.setStyle(s); reference.reset();
            const actual=createTemporaryObject(fixtureComponent,host,{journal:e,indexer:incremental,bottomColor:"#684028"});
            const expected=createTemporaryObject(fixtureComponent,host,{journal:e,indexer:reference,bottomColor:"#684028"});
            wait(120); e.advancePhase();
            while(e.phase==="reversing") {
                e.queueGenerations(1); e.step(4096); incremental.sync();
                actual.flush(); reference.reset(); expected.flush(); wait(40);
                verify(grabImage(actual).equals(grabImage(expected)),"reverse differs from surviving geometry at "+e.segmentCount+" segments");
            }
            compare(e.segmentCount,0);
        }
        function test_contextRestoration() {
            const scene=makeFixture(2,true,true), f=scene.item, before=grabImage(f);
            f.resources=false; wait(50); f.resources=true; wait(150);
            verify(before.equals(grabImage(f)),"new Canvas resources reconstruct the complete journal");
        }
        function test_speedIndependentOfPaintCap() {
            const s=Settings.defaults(); s.RandomizeEachCycle=false;
            const slow=createTemporaryObject(viewComponent,host,{settings:s,fps:5});
            const fast=createTemporaryObject(viewComponent,host,{settings:s,fps:15});
            wait(1250); slow.active=false; fast.active=false;
            verify(slow.engine.totalGenerationCount>=25);
            verify(Math.abs(slow.engine.totalGenerationCount-fast.engine.totalGenerationCount)<=3,"paint cap must not multiply growth speed");
        }
        function test_holdingDelaySurvivesPause() {
            const s=Settings.defaults(); s.RandomizeEachCycle=false; s.Density=0.1; s.InitialBranches=1; s.CycleDelay=1;
            const v=createTemporaryObject(viewComponent,host,{width:72,height:72,settings:s});
            tryCompare(v,"phase","holding"); wait(150); v.active=false;
            const serial=v.engine.phaseSerial, operations=v.operationCount;
            wait(1500); compare(v.engine.phaseSerial,serial); compare(v.operationCount,operations);
            v.active=true; wait(600); compare(v.engine.phaseSerial,serial);
            wait(500); verify(v.engine.phaseSerial>serial);
        }
        function test_missingBackgroundFallsBackWithoutStopping() {
            const s=Settings.defaults(); s.BackgroundMode="image"; s.BackgroundColor="#183048"; s.BackgroundImage="file:///nonexistent-city-grow-proof/background.png"; s.RandomizeEachCycle=false;
            const v=createTemporaryObject(viewComponent,host,{settings:s,active:false});
            tryCompare(v,"imageError",true);
            wait(100); compare(grabImage(v).pixel(20,20),Qt.rgba(24/255,48/255,72/255,1));
            v.active=true; wait(200); verify(v.operationCount>0);
        }
        function test_pauseAndResume() {
            const s=Settings.defaults(); s.InitialBranches=10; s.RandomizeEachCycle=false;
            const v=createTemporaryObject(viewComponent,host,{settings:s});
            wait(1000); verify(v.operationCount>0); verify(v.paintCount>0);
            v.active=false; wait(250);
            const operations=v.operationCount, paints=v.paintCount, generations=v.engine.totalGenerationCount;
            wait(5000); compare(v.operationCount,operations); compare(v.paintCount,paints);
            v.active=true; wait(250); verify(v.operationCount>operations);
            verify(v.engine.totalGenerationCount-generations<=10,"resume does not simulate hidden wall time");
        }
        function test_zeroResizeAndStylePreservesGeometry() {
            const s=Settings.defaults(); s.RandomizeEachCycle=false;
            const v=createTemporaryObject(viewComponent,host,{width:0,height:0,settings:s,active:false});
            wait(50); compare(v.engine.capacity,0); compare(v.phase,"finished");
            v.width=800; v.height=600; v.active=true; wait(300); v.active=false; wait(100);
            verify(v.engine.segmentCount>0);
            const engine=v.engine, segments=engine.segmentCount;
            const changed=Object.assign({},s,{Palette:"ember",FillCity:false,LineWidth:1.5});
            v.settings=changed; wait(120);
            verify(v.engine===engine); compare(v.engine.segmentCount,segments);
            v.width=400; wait(100); verify(v.engine!==engine); compare(v.engine.columns,Math.floor(400/6));
        }
    }
}
