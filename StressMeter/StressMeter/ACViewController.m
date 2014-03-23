//
//  ACViewController.m
//  StressMeter
//
//  Created by Doug Wait on 3/11/14.
//  Copyright (c) 2014 Doug Wait. All rights reserved.
//

//
// I used this example code during a presentation to the Atlanta iOS Developers March 2014 Meetup.
// It is generally written for simplicity and isn't necessarily the best structure or style but
// rather it is intended to be clear and concise.
//
// The code demonstrates the basic 13 step process to discover, connect to, and acquire a heart
// rate measurement from a Bluetootl 4.0 peripheral. To run the demo you will need
// an iOS device with Bluetooth LE support and a Bluetooth 4 heart rate sensor.
//
// This example does not include saving devices and restoring them, handling background mode,
// writing to control points, multiple CBCentralManagers, or using Core Bluetooth in the
// peripheral mode (i.e. iOS as peripheral). I hope to cover these areas in a future presentation.
//
//                                                      -Doug
//

#import "ACViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>

// Service UUIDs
NSString * const HeartRateServiceUUIDString = @"0x180D";
NSString * const DeviceInformationUUIDString = @"0x180A";

// Heart Rate Service Characteristic UUIDs
NSString * const HeartRateMeasurementCharacteristicUUIDString = @"0x2A37";
NSString * const BodySensorLocationCharacteristicUUIDString = @"0x2A38";

// Device Information Characteristic UUIDs
NSString * const ManufacturerNameCharacteristicUUIDString = @"0x2A29";
NSString * const ModelNumberCharacteristicUUIDString = @"0x2A24";
NSString * const HardwareRevisionCharacteristicUUIDString = @"0x2A27";


//
// Flags for heart rate characteristic
//
//    Heart rate format (bit 0)
//    0 == UINT8
//    1 == UINT16
//
//    Sensor contact status (bits 1-2)
//    0 == feature not supported
//    1 == feature not supported
//    2 == feature supported no contact
//    3 == feature supported contact
//
//    Energy expended status (bit 3)
//    0 == not present
//    1 == present
//
//    RR-Interval values (bit 4)
//    0 == not present
//    1 == present
//
//    Reserved (bits 5-7)

enum {
    HRFormatUINT16Mask = 0x01 << 0,
    HRSensorInContactMask = 0x01 << 1,
    HRSensorContactSupportedMask = 0x01 << 2,
    HREnergyExpendedMask = 0x01 << 3,
    HRRRIntervalPresentMask = 0x01 << 4
};


@interface ACViewController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property(strong, nonatomic) CBCentralManager *hrCBManager;
@property(strong, nonatomic) CBPeripheral *hrSensor;

@property (weak, nonatomic) IBOutlet UILabel *heartRateValueLabel;
@property (weak, nonatomic) IBOutlet UILabel *heartRateLabel;

@property (weak, nonatomic) IBOutlet UILabel *inContactLabel;

@property (weak, nonatomic) IBOutlet UILabel *rrIntervalsValueLabel;
@property (weak, nonatomic) IBOutlet UILabel *rrIntervalsLabel;

@end

@implementation ACViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.inContactLabel.text = @"No Contact";
    self.hrCBManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)renderHeartRateMeasurement:(NSData *)value {
    
    // Decode the value (flags and heart rate)
    //
    // Example with 16 bit heart rate, energy expended, and zero or more RR-Interval values
    //   +--------+--------+--------+--------+--------+--------+--------+--------+--------
    //   | flags  | HR 16           | Energy Expended | RR-Interval 0   | RR-Interval 1 ...
    //   +--------+--------+--------+--------+--------+--------+--------+--------+--------
    //
    // Example with 8 bit heart rate and zero or more RR-Interval values
    //   +--------+--------+--------+--------+--------+--------
    //   | flags  | HR 8   | RR-Interval 0   | RR-Interval 1 ...
    //   +--------+--------+--------+--------+--------+--------
    //
    const uint8_t *bytes = value.bytes;
    int curIndex = 0; // use this to track where we are in the value (array of bytes)
    
    uint8_t flags = bytes[curIndex];
    curIndex += sizeof(uint8_t);
    
    BOOL contactFeatureSupported = (flags & HRSensorContactSupportedMask) == HRSensorContactSupportedMask;
    BOOL inContact = contactFeatureSupported && ((flags & HRSensorInContactMask) == HRSensorInContactMask);
    BOOL rrIntervalPresent = (flags & HRRRIntervalPresentMask) == HRRRIntervalPresentMask;
    BOOL energyExpendedPresent = (flags & HREnergyExpendedMask) == HREnergyExpendedMask;
    
    NSLog(@"contact supported %d, incontact %d, rrIntervalPresent %d, energyExpendedPresent %d",
          contactFeatureSupported,inContact,rrIntervalPresent,energyExpendedPresent);
    
    // Check heart rate format
    uint16_t heartRate = 0;
    
    if ((flags & HRFormatUINT16Mask) == HRFormatUINT16Mask) {
        heartRate = CFSwapInt16LittleToHost(*(uint16_t *)(&bytes[curIndex]));
        curIndex += sizeof(uint16_t);
    } else {
        heartRate = ((const uint8_t *)bytes)[curIndex];
        curIndex += sizeof(uint8_t);
    }
    
    // TODO: decode energy expedned
    if (energyExpendedPresent) {
        curIndex += sizeof(uint16_t);
    }
    
    NSString *rrValueString = @"";
    while (rrIntervalPresent && curIndex < value.length) {
        uint16_t rrInterval = CFSwapInt16LittleToHost(*(uint16_t *)(&bytes[curIndex]));
        rrValueString = [NSString stringWithFormat:@"%@ %d",rrValueString,rrInterval];
        curIndex += sizeof(uint16_t);
    }
    
    NSLog(@"Heart Rate: %d, In contact %d, rr intervals %@",heartRate, inContact, rrValueString);
    
    // Update the UI
    self.inContactLabel.text = inContact ? @"Contact" : @"No Contact";
    self.heartRateValueLabel.text = [NSString stringWithFormat:@"%d", heartRate];
    self.rrIntervalsValueLabel.text = rrValueString;
    
    self.rrIntervalsLabel.textColor = rrIntervalPresent ? [UIColor blueColor] : [UIColor redColor];
    self.heartRateLabel.textColor = self.inContactLabel.textColor = inContact ? [UIColor blueColor] : [UIColor redColor];
}


#pragma mark CBCentralManagerDelegate methods

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    
    switch (central.state) {
        case CBCentralManagerStatePoweredOn:
            NSLog(@"central %@ powered on",central);
            // Start scanning for peripherals offering the heart rate service. We'll
            // pick up any peripheral in range that offers this service.
            [self.hrCBManager scanForPeripheralsWithServices:@[
                                    [CBUUID UUIDWithString:HeartRateServiceUUIDString]
                                ] options:nil];
            break;
        case CBCentralManagerStatePoweredOff:
        case CBCentralManagerStateResetting:
        case CBCentralManagerStateUnauthorized:
        case CBCentralManagerStateUnknown:
        case CBCentralManagerStateUnsupported:
            NSLog(@"central %@ state changed to: %ld",central,(long)central.state);
        default:
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI
{
    NSLog(@"discovered peripheral: %@",peripheral);
    NSLog(@"advertisement data: %@",advertisementData);
    NSLog(@"RSSI: %@",RSSI);
    
    // Since we're going to try to connect the peripheral we need to hang on
    // to a reference. In this simple example we're just connecting to
    // one peripheral so we'll just accomodate one. We could use a collection.
    // You can even use peripheral as a dictionary key.
    
    self.hrSensor = peripheral;
    
    // We've found one so let's stop scanning
    [self.hrCBManager stopScan];
    
    // Now we'll try to connect to the peripheral
    [self.hrCBManager connectPeripheral:self.hrSensor options:nil];
    
}


- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    
    NSLog(@"connected to %@",peripheral);
    
    // become the delegate for the peripheral
    peripheral.delegate = self;
    
    // Now we need to really gain access to the HR service and
    // device information service so we will now discover those
    // on this peripheral
    [peripheral discoverServices:@[
                            [CBUUID UUIDWithString:HeartRateServiceUUIDString],
                            [CBUUID UUIDWithString:DeviceInformationUUIDString]
                        ]];
}

#pragma mark CBPeripheralDelegate methods

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    
    NSLog(@"peripheral %@ discovered services %@",peripheral,peripheral.services);
    
    // In particular we're looking for heart rate service and device information
    for (CBService *service in peripheral.services) {
        
        // We'll keep it simple for the demo but there are more sophisticated ways
        // of working through the array if you're dealing with a more complicated
        // scenario
        if ( [service.UUID isEqual:[CBUUID UUIDWithString:HeartRateServiceUUIDString]] ) {
            
            [peripheral discoverCharacteristics:@[
                                    [CBUUID UUIDWithString:HeartRateMeasurementCharacteristicUUIDString],
                                    [CBUUID UUIDWithString:BodySensorLocationCharacteristicUUIDString]
                                ]
                                     forService:service];
            
        } else if ( [service.UUID isEqual:[CBUUID UUIDWithString:DeviceInformationUUIDString]] ) {
            
            [peripheral discoverCharacteristics:@[
                                    [CBUUID UUIDWithString:ManufacturerNameCharacteristicUUIDString],
                                    [CBUUID UUIDWithString:ModelNumberCharacteristicUUIDString],
                                    [CBUUID UUIDWithString:HardwareRevisionCharacteristicUUIDString]
                                ]
                                     forService:service];
            
        }
    }
}


-  (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    
    
    // We want to read all of the characteristics except for
    // the Heart Rate Measurement. The Heart Rate Measurement we
    // want to subscribe to.
    //
    for (CBCharacteristic *characteristic in service.characteristics) {
        
        if ( [characteristic.UUID isEqual:[CBUUID UUIDWithString:HeartRateMeasurementCharacteristicUUIDString]] ) {
            if (characteristic.properties & CBCharacteristicPropertyNotify) {
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            } else {
                NSLog(@"HR sensor non-compliant with spec. HR measurement not NOTIFY");
            }
        } else {
            if (characteristic.properties & CBCharacteristicPropertyRead) {
                [peripheral readValueForCharacteristic:characteristic];
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"peripheral: %@",peripheral);
    NSLog(@"updated characteristic: %@",characteristic);
    NSLog(@"to value: %@",characteristic.value);
    
    [self renderHeartRateMeasurement:characteristic.value];
}

@end
