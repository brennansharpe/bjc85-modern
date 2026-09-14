"""Bounded, read-only Classic resource-fork inventory and UI geometry decoder.

Input .rsrc forks remain untouched. Raw payloads and decoded Canon material go
only into ignored research storage. No code resource/decompressor is executed.
"""
import argparse
import csv
from hashlib import sha256
import json
from pathlib import Path
import struct

def unpack(data, offset, fmt):
    size = struct.calcsize(fmt)
    if offset < 0 or offset + size > len(data): raise ValueError('Field exceeds container')
    return struct.unpack_from(fmt, data, offset)

def pascal(data, offset):
    if offset >= len(data): raise ValueError('Missing Pascal string')
    length = data[offset]
    if offset + 1 + length > len(data): raise ValueError('Truncated Pascal string')
    return data[offset+1:offset+1+length].decode('mac_roman'), offset+1+length

def rectangle(data, offset=0):
    top, left, bottom, right = unpack(data, offset, '>hhhh')
    return dict(left=left, top=top, right=right, bottom=bottom)

def decode(kind, data):
    if kind == 'DLOG':
        title, _ = pascal(data, 20)
        return dict(bounds=rectangle(data), item_list_id=unpack(data, 18, '>h')[0], title=title)
    if kind == 'DITL':
        count = unpack(data, 0, '>H')[0] + 1
        offset, items = 2, []
        if count > 4096: raise ValueError('Implausible item count')
        for number in range(1, count+1):
            raw_type, length = unpack(data, offset+12, '>BB')
            payload = data[offset+14:offset+14+length]
            if len(payload) != length: raise ValueError('Truncated dialog item')
            item_type = raw_type & 127
            item = dict(item_number=number, item_type=item_type, disabled=bool(raw_type & 128), bounds=rectangle(data, offset+4))
            if item_type in (4,5,6,8,16): item['label'] = payload.decode('mac_roman')
            elif item_type in (7,32,64) and length == 2: item['referenced_id'] = unpack(payload, 0, '>h')[0]
            items.append(item)
            offset += 14+length+(length & 1)
        return dict(items=items)
    if kind == 'MENU':
        title, offset = pascal(data, 12)
        items = []
        while offset < len(data) and data[offset]:
            label, offset = pascal(data, offset)
            icon, key, mark, style = unpack(data, offset, '>BBBB'); offset += 4
            items.append(dict(label=label, icon=icon, command_key=chr(key) if key else None, mark=mark, style=style))
        return dict(menu_id=unpack(data,0,'>h')[0],title=title,items=items)
    if kind == 'STR ':
        return dict(text=pascal(data,0)[0])
    if kind == 'STR#':
        count=unpack(data,0,'>H')[0]; offset=2; strings=[]
        for _ in range(count):
            value,offset=pascal(data,offset); strings.append(value)
        return dict(strings=strings)
    return None

def fork_bytes(data):
    if unpack(data,0,'>I')[0] in (0x00051607,0x00051600):
        count=unpack(data,24,'>H')[0]
        for index in range(count):
            kind,offset,length=unpack(data,26+index*12,'>III')
            if kind == 2:
                if offset+length>len(data): raise ValueError('AppleDouble fork exceeds file')
                return data[offset:offset+length]
        raise ValueError('AppleDouble has no resource fork')
    return data

def resources(container):
    data=fork_bytes(container)
    data_at, map_at, data_size, map_size = unpack(data,0,'>IIII')
    if min(data_at,map_at) < 16 or data_at+data_size > len(data) or map_at+map_size > len(data):
        raise ValueError('Invalid resource fork extents')
    resource_data=data[data_at:data_at+data_size]; resource_map=data[map_at:map_at+map_size]
    type_offset, name_offset = unpack(resource_map,24,'>HH')
    count = (unpack(resource_map,type_offset,'>H')[0] + 1) & 65535
    if count > 4096: raise ValueError('Implausible resource type count')
    for i in range(count):
        kind, minus_one, ref_offset = unpack(resource_map,type_offset+2+i*8,'>4sHH')
        for j in range(minus_one+1):
            position=type_offset+ref_offset+j*12
            resource_id, name, attributes_offset, _ = unpack(resource_map,position,'>hHII')
            offset=attributes_offset & 0xffffff
            length=unpack(resource_data,offset,'>I')[0]
            payload=resource_data[offset+4:offset+4+length]
            if len(payload) != length: raise ValueError('Resource exceeds data area')
            yield dict(type=kind.decode('mac_roman'),id=resource_id,name=None if name==65535 else pascal(resource_map,name_offset+name)[0],
                       attributes=attributes_offset>>24,length=length,sha256=sha256(payload).hexdigest()),payload

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('source',type=Path); parser.add_argument('output',type=Path)
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    index=[]; rows=[]
    for source in sorted(args.source.rglob('*.rsrc')):
        data=source.read_bytes(); digest=sha256(data).hexdigest()
        folder=args.output/digest; folder.mkdir(exist_ok=True)
        entry=dict(source=str(source),sha256=digest,bytes=len(data),resource_fork_sha256=sha256(fork_bytes(data)).hexdigest(),resources=[])
        for resource,payload in resources(data):
            kind=resource['type']; name=f"{kind.encode('mac_roman').hex()}-{resource['id']}"
            raw=folder/(name+'.bin'); raw.write_bytes(payload)
            resource['raw_output']=str(raw)
            if resource['attributes'] & 1:
                resource['note']='Compressed resource retained; no embedded decompressor executed.'
            else:
                try: decoded=decode(kind,payload)
                except (ValueError,struct.error) as error: decoded=dict(decode_error=str(error))
                if decoded is not None:
                    target=folder/(name+'.json'); target.write_text(json.dumps(decoded,indent=2,ensure_ascii=False)+'\n')
                    resource.update(decoded_output=str(target),decoded_sha256=sha256(target.read_bytes()).hexdigest())
                    for item in decoded.get('items',[]):
                        bounds=item.get('bounds',{})
                        rows.append(dict(source=str(source),type=kind,id=resource['id'],item=item.get('item_number',''),label=item.get('label',''),
                                         left=bounds.get('left',''),top=bounds.get('top',''),right=bounds.get('right',''),bottom=bounds.get('bottom','')))
            entry['resources'].append(resource)
        index.append(entry)
    (args.output/'index.json').write_text(json.dumps(index,indent=2,ensure_ascii=False)+'\n')
    with (args.output/'ui-items.csv').open('w',newline='') as output:
        writer=csv.DictWriter(output,fieldnames=['source','type','id','item','label','left','top','right','bottom'])
        writer.writeheader(); writer.writerows(rows)
    print(json.dumps(dict(forks=len(index),resources=sum(len(x['resources']) for x in index),ui_items=len(rows),output=str(args.output))))

if __name__ == '__main__': main()
