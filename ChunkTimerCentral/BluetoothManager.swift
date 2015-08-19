//
//  BluetoothManager.swift
//  ChunkTimerCentral
//
//  Created by Jay Tucker on 6/30/15.
//  Copyright (c) 2015 Imprivata. All rights reserved.
//

import Foundation
import CoreBluetooth

class BluetoothManager: NSObject {
    
    private let serviceUUID                = CBUUID(string: "193DB24F-E42E-49D2-9A70-6A5616863A9D")
    private let requestCharacteristicUUID  = CBUUID(string: "43CDD5AB-3EF6-496A-A4CC-9933F5ADAF68")
    private let responseCharacteristicUUID = CBUUID(string: "F1A9A759-C922-4219-B62C-1A14F62DE0A4")
    
    private let timeoutInSecs = 5.0
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    private var responseCharacteristic: CBCharacteristic!
    private var requestCharacteristic: CBCharacteristic!
    private var isPoweredOn = false
    private var scanTimer: NSTimer!
    
    private var isBusy = false
    
    private let dechunker = Dechunker()
    
    private let chunkSize = 19
    private var nChunks = 0
    private var nChunksSent = 0
    private var startTime = NSDate()
    
    private let moby = "Call me Ishmael. Some years ago - never mind how long precisely - having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world. It is a way I have of driving off the spleen and regulating the circulation. Whenever I find myself growing grim about the mouth; whenever it is a damp, drizzly November in my soul; whenever I find myself involuntarily pausing before coffin warehouses, and bringing up the rear of every funeral I meet; and especially whenever my hypos get such an upper hand of me, that it requires a strong moral principle to prevent me from deliberately stepping into the street, and methodically knocking people's hats off - then, I account it high time to get to sea as soon as I can. This is my substitute for pistol and ball. With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship. There is nothing surprising in this. If they but knew it, almost all men in their degree, some time or other, cherish very nearly the same feelings towards the ocean with me."
    
    var mobyBytes = [UInt8]()
    
    // See:
    // http://stackoverflow.com/questions/24218581/need-self-to-set-all-constants-of-a-swift-class-in-init
    // http://stackoverflow.com/questions/24441254/how-to-pass-self-to-initializer-during-initialization-of-an-object-in-swift
    override init() {
        super.init()
        
        for codeUnit in moby.utf8 {
            mobyBytes.append(codeUnit)
        }
        
        centralManager = CBCentralManager(delegate:self, queue:nil)
    }
    
    func go() {
        log("go")
        if (isBusy) {
            log("busy, ignoring request")
            return
        }
        isBusy = true
        startTime = NSDate()
        startScanForPeripheralWithService(serviceUUID)
    }
    
    private func startScanForPeripheralWithService(uuid: CBUUID) {
        log("startScanForPeripheralWithService \(nameFromUUID(uuid)) \(uuid)")
        centralManager.stopScan()
        scanTimer = NSTimer.scheduledTimerWithTimeInterval(timeoutInSecs, target: self, selector: Selector("timeout"), userInfo: nil, repeats: false)
        centralManager.scanForPeripheralsWithServices([uuid], options: nil)
    }
    
    // can't be private because called by timer
    func timeout() {
        log("timed out")
        centralManager.stopScan()
        isBusy = false
    }
    
    private func nameFromUUID(uuid: CBUUID) -> String {
        switch uuid {
        case serviceUUID: return "service"
        case requestCharacteristicUUID: return "requestCharacteristic"
        case responseCharacteristicUUID: return "responseCharacteristic"
        default: return "unknown"
        }
    }
    
    private func sendRequest() {
        let chunks = Chunker.makeChunks(mobyBytes, chunkSize: chunkSize)
        log("request is \(mobyBytes.count) bytes (\(chunks.count) chunk(s) of \(chunkSize) bytes)")
        nChunks = chunks.count
        nChunksSent = 0
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            for (i, chunk) in enumerate(chunks) {
                let chunkData = NSData(bytes: chunk, length: chunk.count)
                log("sending chunk \(i + 1)/\(self.nChunks) (\(chunkData.length) bytes)")
                self.peripheral.writeValue(chunkData, forCharacteristic: self.requestCharacteristic, type: CBCharacteristicWriteType.WithoutResponse)
                usleep(25000)
            }
            // self.disconnect()
        }
    }
    
    private func processResponse(responseBytes: [UInt8]) {
        log("processResponse")
        if let response = NSString(bytes: responseBytes, length: responseBytes.count, encoding: NSUTF8StringEncoding) {
            log("got response:")
            log(response as String)
        } else {
            log("failed to parse response")
        }
    }
    
}

extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(central: CBCentralManager!) {
        var caseString: String!
        switch centralManager.state {
        case .Unknown:
            caseString = "Unknown"
        case .Resetting:
            caseString = "Resetting"
        case .Unsupported:
            caseString = "Unsupported"
        case .Unauthorized:
            caseString = "Unauthorized"
        case .PoweredOff:
            caseString = "PoweredOff"
        case .PoweredOn:
            caseString = "PoweredOn"
        default:
            caseString = "WTF"
        }
        log("centralManagerDidUpdateState \(caseString)")
        isPoweredOn = (centralManager.state == .PoweredOn)
        if isPoweredOn {
            // go()
        }
    }
    
    func centralManager(central: CBCentralManager!, didDiscoverPeripheral peripheral: CBPeripheral!, advertisementData: [NSObject : AnyObject]!, RSSI: NSNumber!) {
        log("centralManager didDiscoverPeripheral")
        scanTimer.invalidate()
        centralManager.stopScan()
        self.peripheral = peripheral
        centralManager.connectPeripheral(peripheral, options: nil)
    }
    
    func centralManager(central: CBCentralManager!, didConnectPeripheral peripheral: CBPeripheral!) {
        log("centralManager didConnectPeripheral")
        self.peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
}

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(peripheral: CBPeripheral!, didDiscoverServices error: NSError!) {
        if error == nil {
            log("peripheral didDiscoverServices ok")
        } else {
            log("peripheral didDiscoverServices error \(error.localizedDescription)")
            return
        }
        for service in peripheral.services {
            log("service \(nameFromUUID(service.UUID))  \(service.UUID)")
            peripheral.discoverCharacteristics(nil, forService: service as! CBService)
        }
    }
    
    func peripheral(peripheral: CBPeripheral!, didDiscoverCharacteristicsForService service: CBService!, error: NSError!) {
        if error == nil {
            log("peripheral didDiscoverCharacteristicsForService \(service.UUID) ok")
        } else {
            log("peripheral didDiscoverCharacteristicsForService error \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics {
            let name = nameFromUUID(characteristic.UUID)
            log("characteristic \(name) \(characteristic.UUID)")
            if characteristic.UUID == requestCharacteristicUUID {
                requestCharacteristic = characteristic as! CBCharacteristic
            } else if characteristic.UUID == responseCharacteristicUUID {
                responseCharacteristic = characteristic as! CBCharacteristic
                peripheral.setNotifyValue(true, forCharacteristic: characteristic as! CBCharacteristic)
            }
        }
        sendRequest()
    }
    
    func peripheral(peripheral: CBPeripheral!, didUpdateValueForCharacteristic characteristic: CBCharacteristic!, error: NSError!) {
        if error == nil {
            let name = nameFromUUID(characteristic.UUID)
            log("peripheral didUpdateValueForCharacteristic \(name) ok")
            log("received chunk (\(characteristic.value.length) bytes)")
            var chunkBytes = [UInt8](count: characteristic.value.length, repeatedValue: 0)
            characteristic.value.getBytes(&chunkBytes, length: characteristic.value.length)
            let retval = dechunker.addChunk(chunkBytes)
            if retval.isSuccess {
                if let finalResult = retval.finalResult {
                    log("dechunker done")
                    log("received \(finalResult.count) bytes from dechunker")
                    processResponse(finalResult)
                    disconnect()
                } else {
                    // chunk was ok, but more to come
                    log("dechunker ok, but not done yet")
                }
            } else {
                // chunk was faulty
                log("dechunker failed")
                disconnect()
            }
        } else {
            log("peripheral didUpdateValueForCharacteristic error \(error.localizedDescription)")
            disconnect()
        }
    }
    
    private func disconnect() {
        let timeInterval = startTime.timeIntervalSinceNow
        log("disconnect after \(-timeInterval) secs")
        centralManager.cancelPeripheralConnection(peripheral)
        peripheral = nil
        requestCharacteristic = nil
        responseCharacteristic = nil
        isBusy = false
    }
    
}
