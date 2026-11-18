// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihnea Teodor Stoica
// One index per CityView; geometry and randomness belong to its engine.
function createRenderer(engine, width, height, dpr, edge) {
    var columns = Math.ceil(width / edge), rows = Math.ceil(height / edge), tiles = columns * rows;
    var heads = new Int32Array(tiles), tails = new Int32Array(tiles);
    var next = new Int32Array(engine.capacity * 4), previous = new Int32Array(engine.capacity * 4);
    var members = new Int32Array(engine.capacity * 4), memberCount = new Uint8Array(engine.capacity);
    var minX = new Float64Array(tiles), minY = new Float64Array(tiles), maxX = new Float64Array(tiles), maxY = new Float64Array(tiles);
    var rebuild = new Uint8Array(tiles), paintedUntil = new Uint32Array(tiles);
    var bounds = new Float64Array(4), style = null, colors = [], fills = [];
    var spacing = engine.effectiveSpacing;
    heads.fill(-1); tails.fill(-1);
    function clearDirty(t) { minX[t] = width + 1; minY[t] = height + 1; maxX[t] = -1; maxY[t] = -1; }
    for (var t = 0; t < tiles; ++t) clearDirty(t);
    function segmentBounds(id) {
        var a = engine.segmentFrom[id], b = engine.segmentTo[id];
        var ax = a % engine.columns * spacing, ay = Math.floor(a / engine.columns) * spacing;
        var bx = b % engine.columns * spacing, by = Math.floor(b / engine.columns) * spacing;
        // Independent of current fill/line settings, so style changes do not reindex.
        var pad = spacing + 8 + 1 / dpr;
        bounds[0] = Math.max(0, Math.min(ax,bx) - pad);
        bounds[1] = Math.max(0, Math.min(ay,by) - pad);
        bounds[2] = Math.min(width, Math.max(ax,bx) + pad);
        bounds[3] = Math.min(height, Math.max(ay,by) + pad);
    }
    function dirty(t, x0, y0, x1, y1) {
        var ox = t % columns * edge, oy = Math.floor(t / columns) * edge;
        minX[t] = Math.min(minX[t], Math.max(0,x0-ox)); minY[t] = Math.min(minY[t],Math.max(0,y0-oy));
        maxX[t] = Math.max(maxX[t],Math.min(edge,width-ox,x1-ox)); maxY[t] = Math.max(maxY[t],Math.min(edge,height-oy,y1-oy));
    }
    function add(id) {
        segmentBounds(id);
        var x0 = Math.floor(bounds[0]/edge), y0 = Math.floor(bounds[1]/edge);
        var x1 = Math.min(columns-1, Math.floor(Math.max(bounds[0],bounds[2]-0.0001)/edge));
        var y1 = Math.min(rows-1, Math.floor(Math.max(bounds[1],bounds[3]-0.0001)/edge));
        var n = 0;
        for (var y=y0; y<=y1; ++y) for (var x=x0; x<=x1; ++x) {
            if (n === 4) throw new Error('Segment exceeds four tile memberships');
            var tile = y*columns+x, entry = id*4+n++;
            members[entry] = tile; previous[entry] = tails[tile]; next[entry] = -1;
            if (tails[tile] < 0) heads[tile] = entry; else next[tails[tile]] = entry;
            tails[tile] = entry;
            dirty(tile,bounds[0],bounds[1],bounds[2],bounds[3]);
        }
        memberCount[id] = n;
    }
    function remove(id) {
        segmentBounds(id);
        for (var n=0; n<memberCount[id]; ++n) {
            var entry=id*4+n, tile=members[entry], p=previous[entry], q=next[entry];
            if(p<0) heads[tile]=q; else next[p]=q;
            if(q<0) tails[tile]=p; else previous[q]=p;
            rebuild[tile]=1;
            dirty(tile,bounds[0],bounds[1],bounds[2],bounds[3]);
        }
        memberCount[id]=0;
    }
    function allDirty() {
        for(var t=0;t<tiles;++t) { rebuild[t]=1; dirty(t,0,0,width,height); }
    }
    function rgbHue(hex) {
        var r=parseInt(hex.slice(1,3),16)/255,g=parseInt(hex.slice(3,5),16)/255,b=parseInt(hex.slice(5,7),16)/255;
        var max=Math.max(r,g,b),min=Math.min(r,g,b),d=max-min,l=(max+min)/2,h=0,s=0;
        if(d) { s=d/(1-Math.abs(2*l-1)); h=max===r ? ((g-b)/d)%6 : max===g ? (b-r)/d+2 : (r-g)/d+4; h*=60; }
        return [((h+360)%360),s*100,l*100];
    }
    var result = {
        tileColumns:columns, tileRows:rows, tileCount:tiles, edge:edge,
        setStyle:function(settings) {
            style=settings;
            var palettes={aurora:['#66e3c4','#76a9fa','#bb9af7','#e0af68'],ember:['#ff9e64','#e0af68','#f7768e','#db4b4b'],monochrome:['#c0caf5','#a9b1d6','#9aa5ce','#565f89']};
            var palette=palettes[settings.Palette] || (settings.Palette==='custom' ? JSON.parse(settings.CustomColors) : null);
            var count=palette ? palette.length : 256;
            colors=new Array(count*2); fills=new Array(count*2);
            for(var main=0;main<2;++main) for(var i=0;i<count;++i) {
                var hsl=palette ? rgbHue(palette[i]) : [i,100,55];
                var hue=(hsl[0]+settings.HueOffset)%360, light=main ? hsl[2] : hsl[2]*60/140;
                // QColor values avoid Canvas's fractional-HSL CSS parser.
                colors[main*count+i]=Qt.hsla(hue/360,hsl[1]/100,light/100,1);
                fills[main*count+i]=Qt.hsla(hue/360,hsl[1]/100,light/100,settings.FillOpacity);
            }
            result.paletteSize=count; result.originalPalette=!palette;
            allDirty();
        },
        sync:function() {
            for(var i=0;i<engine.changeCount;++i) {
                var change=engine.changeIds[i];
                if(change>0) add(change-1); else remove(-change-1);
            }
        },
        reset:function() {
            heads.fill(-1); tails.fill(-1); memberCount.fill(0); paintedUntil.fill(0);
            for(var id=0;id<engine.journalCount;++id) if(engine.segmentActive[id]) add(id);
            allDirty();
        },
        invalidate:function(tile) {
            rebuild[tile]=1; paintedUntil[tile]=0;
            dirty(tile,0,0,width,height);
        },
        flush:function(callback) {
            for(var t=0;t<tiles;++t) if(maxX[t]>minX[t] && maxY[t]>minY[t]) {
                callback(t,Math.floor(minX[t]),Math.floor(minY[t]),Math.ceil(maxX[t])-Math.floor(minX[t]),Math.ceil(maxY[t])-Math.floor(minY[t]));
                clearDirty(t);
            }
        },
        paint:function(ctx,tile,region) {
            if(!style || !ctx) return;
            var ox=tile%columns*edge,oy=Math.floor(tile/columns)*edge;
            var x=region.x,y=region.y,w=region.width,h=region.height;
            ctx.save(); ctx.beginPath(); ctx.rect(x,y,w,h); ctx.clip();
            if(rebuild[tile]) ctx.clearRect(x,y,w,h);
            ctx.translate(-ox,-oy); ctx.globalCompositeOperation='source-over';
            var first=paintedUntil[tile];
            var lw=Math.min(style.LineWidth,Math.max(0.5,spacing-0.5)),offset=lw/2;
            ctx.lineWidth=lw; ctx.lineCap='butt';
            for(var entry=heads[tile];entry>=0;entry=next[entry]) {
                var id=Math.floor(entry/4);
                if(!rebuild[tile] && id<first) continue;
                segmentBounds(id);
                if(bounds[2]<ox+x || bounds[0]>ox+x+w || bounds[3]<oy+y || bounds[1]>oy+y+h) continue;
                var a=engine.segmentFrom[id],b=engine.segmentTo[id];
                var ax=(a%engine.columns)*spacing+offset,ay=Math.floor(a/engine.columns)*spacing+offset;
                var bx=(b%engine.columns)*spacing+offset,by=Math.floor(b/engine.columns)*spacing+offset;
                var color=engine.segmentMain[id]*result.paletteSize+(result.originalPalette ? engine.segmentHue[id]%256 : engine.segmentColor[id]%result.paletteSize);
                if(style.FillCity && engine.segmentCity[id]) {
                    ctx.fillStyle=fills[color];
                    var size=spacing-lw;
                    if(ay===by) {
                        var left=Math.min(ax,bx)+lw/2;
                        ctx.fillRect(left,ay+lw/2,size,size); ctx.fillRect(left,ay-spacing+lw/2,size,size);
                    } else {
                        var top=Math.min(ay,by)+lw/2;
                        ctx.fillRect(ax+lw/2,top,size,size); ctx.fillRect(ax-spacing+lw/2,top,size,size);
                    }
                }
                ctx.strokeStyle=colors[color]; ctx.beginPath(); ctx.moveTo(ax,ay); ctx.lineTo(bx,by); ctx.stroke();
            }
            ctx.restore(); paintedUntil[tile]=engine.journalCount; rebuild[tile]=0;
        }
    };
    return result;
}
