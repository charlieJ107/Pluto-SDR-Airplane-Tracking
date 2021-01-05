classdef (StrictDefaults)helperAdsbRxMsgParser < matlab.System & matlab.system.mixin.Propagates ...
    & matlab.system.mixin.CustomIcon
  %helperAdsbRxMsgParser ADS-B receiver message parser
  %   PARSER = helperAdsbRxMsgParser creates an ADS-B receiver message
  %   parser System object that parses the physical layer packets and
  %   extracts airplane information
  %
  %   Step method syntax:
  %
  %   [MSG,CNT] = step(PARSER,PKT,CNT) parses the vector of physical layer
  %   packets, PKT, and returns a vector of message structures, MSG. CNT is
  %   the number of valid packets in PKT.
  %
  %   System objects may be called directly like a function instead of using
  %   the step method. For example, y = step(obj, x) and y = obj(x) are
  %   equivalent.
  %
  %   See also ADSBExample, helperAdsbRxPhy.
  
  %   Copyright 2015-2016 The MathWorks, Inc.
  
  %#codegen

  properties
    ADSBParam
  end
  
  properties (Access = private)
    PositionDatabase
    PositionPacketDatabase
    CachedMessagePacket
  end

  properties (Constant, Access = private)
    CharacterCode = ...
      ' ABCDEFGHIJKLMNOPQRSTUVWXYZ                     0123456789      '
  end
  
  methods
    function obj = helperAdsbRxMsgParser(varargin)
      % Support name-value pair arguments
      setProperties(obj,nargin,varargin{:}, 'ADSBParam');

      initDatabases(obj);
      
      obj.CachedMessagePacket = helperAdsbRxMsgParser.msgPacket();
    end
  end
  
  methods (Access = protected)
    function [msg, pktCnt] = stepImpl(obj, pkt, pktCnt)
      adsbParam = obj.ADSBParam;
      
      msg = repmat(obj.CachedMessagePacket,...
        adsbParam.MaxNumPacketsInFrame,1);
      
      for p=1:pktCnt
        % Get an empty packet with added header information
        msg(p,1) = getMessagePacket(obj,pkt(p,1));
        
        if pkt(p,1).CRCError == 0
          % ICAO 24-bit aircraft ID (Hex)
          msg(p,1).ICAO24 = helperAdsbBin2Hex(pkt(p,1).RawBits(9:32,1));
          
          if msg(p,1).Header.DF == 17
            adsbBits = logical(pkt(p,1).RawBits(33:88,1));
            msg(p,1).TC = uint8([16 8 4 2 1]*adsbBits(1:5,1)); % Type Code
            switch msg(p,1).TC
              case {1 2 3 4}
                % Identification
                msg(p,1) = parseIDPacket(obj, adsbBits, msg(p,1));
              case {5 6 7 8}
                % Surface position
              case {9 10 11 12 13 14 15 16 17 18 20 21 22}
                % Airborne Position
                msg(p,1) = parseAirbornePosition(obj, adsbBits, msg(p,1));
              case 19
                msg(p,1).AirborneVelocity = parseVelocityPacket(obj, adsbBits, ...
                  msg(p,1).AirborneVelocity);
              case 28
                % Extended Squitter Aircraft Status/ACAS RA
              case 31
                % Aircraft operational status
            end
          end
        end
      end
    end

    function icon = getIconImpl(~)
      % Return text for the System block icon
      icon = sprintf('ADS-B\nMessage Parser');
    end

    function [sz1,sz2] = getOutputSizeImpl(obj)
      % Return size for each output port
      sz1 = propagatedInputSize(obj,1); % Calculate from input
      sz2 = [1 1];
    end

    function [dt1,dt2] = getOutputDataTypeImpl(~)
      % Return data type for each output port
      dt1 = 'ADSBMessage';
      dt2 = 'double';
    end

    function [cp1,cp2] = isOutputComplexImpl(~)
      % Return true for each output port with complex data
      cp1 = false;
      cp2 = false;
    end

    function [fs1,fs2] = isOutputFixedSizeImpl(~)
      % Return true for each output port with fixed size
      fs1 = true;
      fs2 = true;
    end
  end
  
  methods (Access = private)
    function initDatabases(obj)
      % Data structure to store resolved airplane locations
      %
      % Aircraft IDs:
      %     double 1 x 20
      % Time:
      %     counter value x 20
      % Zone data:
      %     [jSaved1(1);jSaved1(2);jSaved2(1);jSaved2(2);...
      %      mSaved1(1);mSaved1(2);mSaved2(1);mSaved2(2)]
      % Position:
      %     [latitude;longitude]
      % Counter:
      %     Use instead of datenum
      database = struct(...
        'ID', zeros(1,20), ...
        'Time', zeros(1,20), ...
        'ZoneData', zeros(8,20), ...
        'Position', zeros(2,20), ...
        'Counter', uint64(0));
      obj.PositionDatabase = database;
      
      % Data structure to store even or odd location packet for airplanes with
      % unresolved location
      %
      % Aircraft IDs:
      %     double 1 x 20
      % CPR Format (even or odd):
      %     double 1 x 20
      % Time:
      %     counter value x 20
      % Latitude:
      %     double 1x20
      % Longitude:
      %     double 1x20
      posPktDatabase = struct(...
        'ID', zeros(1,20), ...
        'CPRFormat', repmat(ADSBCPRFormat.CPRFormatUnset, 1, 20), ...
        'Time', zeros(1,20), ...
        'Latitude', zeros(1,20), ...
        'Longitude', zeros(1,20));
      obj.PositionPacketDatabase = posPktDatabase;
    end
    
    function packet = parseIDPacket(obj, adsbBits, packet)
      %parseIDPacket Identification packet parser
      %   P=parseIDPacket(X,P,ADSB) extracts the identification information from
      %   received data bits, X. P is the ADS-B packet structure. This function
      %   fills in the fields of the Identification field, which contains
      %   following fields:
      %
      %   VehicleCategory : of type ADSBVehicleCategory
      %   FlightID        : 8 character flight ID
      
      Subtype = [4 2 1]*adsbBits(6:8,1);
      switch packet.TC
        case 1
          % Category D
        case 2
          % Category C
          switch Subtype
            case 0
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.NoData;
            case 1
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.EmergencyVehicle;
            case 2
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.ServiceVehicle;
            case 3
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.FixedTetheredObstruction;
            case 4
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.ClusterObstacle;
            case 5
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.LineObstacle;
            case 6
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.VehicleCategoryReserved;
            case 7
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.VehicleCategoryReserved;
          end
        case 3
          % Category B
          switch Subtype
            case 0
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.NoData;
            case 1
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Glider;
            case 2
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.LighterThanAir;
            case 3
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Parachute;
            case 4
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.HangGlider;
            case 5
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.VehicleCategoryReserved;
            case 6
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.UAV;
            case 7
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Spacecraft;
          end
        case 4
          % Category A
          switch Subtype
            case 0
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.NoData;
            case 1
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Light;
            case 2
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Medium;
            case 3
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Heavy;
            case 4
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.HighVortex;
            case 5
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.VeryHeavy;
            case 6
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.HighPerformanceHighSpeed;
            case 7
              packet.Identification.VehicleCategory = ...
                ADSBVehicleCategory.Rotorcraft;
          end
      end
      charValues = [32 16 8 4 2 1]*reshape(adsbBits(9:56,1),6,8)+1;
      packet.Identification.FlightID = obj.CharacterCode(charValues);
    end
    
    function packet = parseVelocityPacket(~, adsbBits, packet)
      %parseVelocityPacket Airborne velocity packet parser
      %   P=parseVelocityPacket(X,P,ADSB) extracts the identification information
      %   from received data bits, X. P is the ADS-B packet structure. This
      %   function fills in the fields of the Identification field, which
      %   contains following fields:
      %
      %   Subtype               : of type ADSBVelocitySubtype
      %   IntentChange          : 0: no change in intent, 1: intent change
      %   IFRCapability
      %   VelocityUncertainty  : Horizontal and vertical velocity error (95%)
      %                         : 0: Unknown
      %                         : 1: <10 m/s  / <15.2 m/s (50 fps)
      %                         : 2: <3 m/s   / <4.6 m/s  (15 fps)
      %                         : 3: <1 m/s   / <1.5 m/s  (5 fps)
      %                         : 4: <0.3 m/s / <0.46 m/s (1.5 fps)
      %   Speed                 : in knots
      %   Heading               : in degrees relative to North
      %   HeadingSymbol         : 'N ','NE','E ','SE','S ','SW','W ','NW'
      %   VerticalRateSource    : 0: GNSS, 1: Baro
      %   VerticalRate          : in feet/minute
      %   TurnIndicator
      %   GHD
      
      Subtype = [4 2 1]*adsbBits(6:8,1);
      switch Subtype
        case {0,5,6,7}
          packet.Subtype = ADSBVelocitySubtype.VehicleSubtypeReserved;
        case 1
          packet.Subtype = ADSBVelocitySubtype.CartesianNormal;
        case 2
          packet.Subtype = ADSBVelocitySubtype.CartesianSupersonic;
        case 3
          packet.Subtype = ADSBVelocitySubtype.PolarNormal;
        case 4
          packet.Subtype = ADSBVelocitySubtype.PolarSupersonic;
      end
      
      packet.IntentChange        = adsbBits(9,1);
      packet.IFRCapability       = adsbBits(10,1);
      packet.VelocityUncertainty = uint8([4 2 1]*adsbBits(11:13,1));
      
      packet.Speed = 0;
      packet.Heading = 0;
      if (packet.Subtype == ADSBVelocitySubtype.CartesianNormal) || ...
          (packet.Subtype == ADSBVelocitySubtype.CartesianSupersonic)
        
        if (packet.Subtype == ADSBVelocitySubtype.CartesianNormal)
          stepSize = 1;
        else
          stepSize = 4;
        end
        
        value = [512 256 128 64 32 16 8 4 2 1]*adsbBits(15:24,1);
        if value ~= 0
          eastWestVelocity = (1-2*adsbBits(14,1))*(value-1)*stepSize;
        else
          eastWestVelocity = NaN;
        end
        value = [512 256 128 64 32 16 8 4 2 1]*adsbBits(26:35,1);
        if value ~= 0
          northSouthVelocity = (1-2*adsbBits(25,1))*(value-1)*stepSize;
        else
          northSouthVelocity = NaN;
        end
        
        [heading,speed] = cart2pol(eastWestVelocity,northSouthVelocity);
        packet.Speed    = round(speed); % Knots
        
        heading = heading*180/pi;
        if heading<0
          heading = 360+heading;
        end
        heading = mod(450-heading,360);
        sectorAngle = 45;
        if heading>=0 && heading<(sectorAngle/2)
          dir = 'N ';
        elseif heading>=(sectorAngle/2) && heading<(3*sectorAngle/2)
          dir = 'NE';
        elseif heading>=(3*sectorAngle/2) && heading<(5*sectorAngle/2)
          dir = 'E ';
        elseif heading>=(5*sectorAngle/2) && heading<(7*sectorAngle/2)
          dir = 'SE';
        elseif heading>=(7*sectorAngle/2) && heading<(9*sectorAngle/2)
          dir = 'S ';
        elseif heading>=(9*sectorAngle/2) && heading<(11*sectorAngle/2)
          dir = 'SW';
        elseif heading>=(11*sectorAngle/2) && heading<(13*sectorAngle/2)
          dir = 'W ';
        elseif heading>=(13*sectorAngle/2) && heading<(15*sectorAngle/2)
          dir = 'NW';
        else
          dir = 'NA';
        end
        packet.Heading = round(heading);
        packet.HeadingSymbol  = dir;
      end
      
      % Vertical velocity is feet/min
      packet.VerticalRateSource = adsbBits(36,1);
      value = [256 128 64 32 16 8 4 2 1]*adsbBits(38:46,1);
      if value ~= 0
        packet.VerticalRate = (1-2*adsbBits(37,1))*(value-1)*64;
      else
        packet.VerticalRate = NaN;
      end
      
      packet.TurnIndicator = [2 1]*adsbBits(47:48,1);
      
      packet.GHD = ...
        (1-2*adsbBits(49,1))*([64 32 16 8 4 2 1]*adsbBits(50:56,1));
    end
    
    function packet = parseAirbornePosition(obj, adsbBits,packet)
      %parseAirbornePosition Airborne position packet parser
      %   P=parseAirbornePosition(X,P,ADSB) extracts the airborne position and
      %   related information from received data bits, X. P is the ADS-B packet
      %   structure. This function fills in the fields of the AirbornePosition
      %   field, which contains following fields:
      %
      %   Status                : of type ADSBStatus
      %   DiversityAntenna      : 1: single antenna, 0: dual antenna
      %   Altitude              : Altitude (foot)
      %   UTCSynchronized       : 0: NOT synchronized to UTC, 1: synchronized
      %   Longitude
      %   Latitude
      
      status = [2 1]*adsbBits(6:7,1);
      switch status
        case 0
          packet.AirbornePosition.Status = ADSBStatus.NoEmergency;
        case 1
          packet.AirbornePosition.Status = ADSBStatus.PermanentAlert;
        case 2
          packet.AirbornePosition.Status = ADSBStatus.TemporaryAlert;
        case 3
          packet.AirbornePosition.Status = ADSBStatus.SPI;
      end
      
      packet.AirbornePosition.DiversityAntenna = adsbBits(8,1);
      
      if any(packet.TC==[20 21 22])
        % GNSS height above (WGS-84) ellipsoid (HAE)
        packet.AirbornePosition.Altitude = ...
          [2048 1024 512 256 128 64 32 16 8 4 2 1]*adsbBits(9:20,1);
      else
        % Barometric altitude
        if adsbBits(16,1) == 1
          altStep = 25;
        else
          altStep = 100;
        end
        packet.AirbornePosition.Altitude = (altStep * ...
          [1024 512 256 128 64 32 16 8 4 2 1]*adsbBits([9:15 17:20],1)) - 1000;
      end
      
      packet.AirbornePosition.UTCSynchronized = adsbBits(21,1);
      
      i = adsbBits(22,1); % 0: Even or 1: odd
      packet.AirbornePosition.CPRFormat = ADSBCPRFormat(uint8(i));
      
      % Nb = 17;
      nbFactor = 131072; % 2^Nb
      Nz = 15;
      
      bitMask17 = ...
        [65536 32768 16384 8192 4096 2048 1024 512 256 128 64 32 16 8 4 2 1];
      
      [savedLat,savedLon,jSaved1,jSaved2,mSaved1,mSaved2] = ...
        getSavedPosition(obj, packet.ICAO24);
      
      % Extract YZi and XZi (the latitude/longitude that a receiving ADS-B
      % system will extract from the transmitted message). Divide by 2^Nb to
      % get percent value.
      YZper = zeros(2,1);
      YZper(i+1,1) = bitMask17 * adsbBits(23:39,1) / nbFactor;
      XZper = zeros(2,1);
      XZper(i+1,1) = bitMask17 * adsbBits(40:56,1) / nbFactor;
      
      if ~isnan(savedLat)
        % If we have a saved position
        
        Dlati = 360/(4*Nz-i);
        
        % Latitude zone number, j
        j = jSaved1(i+1) ...
          + floor(0.5 + jSaved2(i+1) - YZper(i+1,1));
        
        Rlati = Dlati*(j+YZper(i+1,1));
        
        % Compare latitude to known location. If it's off by more than two
        % degrees, use new zone number.
        if Rlati > savedLat+2
          Rlati = Dlati*(j-1+YZper(i+1,1));
        elseif Rlati < savedLat-2
          Rlati = Dlati*(j+1+YZper(i+1,1));
        end
        
        NL = helperAdsbNL(Rlati);
        if NL-i > 0
          Dloni = 360/(NL-i);
        else
          Dloni = 360;
        end
        
        % Longitude zone number, m
        m = mSaved1(i+1) ...
          + floor(0.5 + mSaved2(i+1) - XZper(i+1,1));
        
        Rloni = Dloni*(m+XZper(i+1,1));
        
        % Compare longitude to known location. If it's off by more than two
        % degrees, use new zone number.
        if Rloni > savedLon+2
          Rloni = Dloni*(m-1+XZper(i+1,1));
        elseif Rloni < savedLon-2
          Rloni = Dloni*(m+1+XZper(i+1,1));
        end
      else
        % We do not have a saved position. We need both an odd and an even
        % packet that is not separated by more than 10 seconds.
        
        if packet.AirbornePosition.CPRFormat == ADSBCPRFormat.Even
          % Check if we have an odd packet stored
          [YZper(uint8(ADSBCPRFormat.Odd)+1,1),...
            XZper(uint8(ADSBCPRFormat.Odd)+1,1)] = ...
            getPositionPacket(obj, ...
            packet.ICAO24,...
            ADSBCPRFormat.Odd,...
            packet.Header.Time);
        else
          % Check if we have an even packet stored
          [YZper(uint8(ADSBCPRFormat.Even)+1,1),...
            XZper(uint8(ADSBCPRFormat.Even)+1,1)] = ...
            getPositionPacket(obj, ...
            packet.ICAO24,...
            ADSBCPRFormat.Even,...
            packet.Header.Time);
        end
        
        if any(isnan(YZper))
          setPositionPacket(obj, packet.ICAO24,...
            packet.AirbornePosition.CPRFormat,...
            packet.Header.Time,...
            YZper(uint8(packet.AirbornePosition.CPRFormat)+1,1),...
            XZper(uint8(packet.AirbornePosition.CPRFormat)+1,1));
          Rlati = NaN;
          Rloni = NaN;
        else
          
          Dlat0 = 360/(4*Nz-0);
          Dlat1 = 360/(4*Nz-1);
          
          % Latitude index, j
          j = floor(59*YZper(uint8(ADSBCPRFormat.Even)+1,1) ...
            - 60*YZper(uint8(ADSBCPRFormat.Odd)+1,1) + 0.5);
          
          Rlat0 = Dlat0*(modDegree(j,60-0)+YZper(uint8(ADSBCPRFormat.Even)+1,1));
          if Rlat0 > 270
            Rlat0 = Rlat0 - 360;
          end
          Rlat1 = Dlat1*(mod(j,60-1)+YZper(uint8(ADSBCPRFormat.Odd)+1,1));
          if Rlat1 > 270
            Rlat1 = Rlat1 - 360;
          end
          NL = zeros(2,1);
          NL(uint8(ADSBCPRFormat.Even)+1,1) = helperAdsbNL(Rlat0);
          NL(uint8(ADSBCPRFormat.Odd)+1,1) = helperAdsbNL(Rlat1);
          if NL(uint8(ADSBCPRFormat.Even)+1) ~= NL(uint8(ADSBCPRFormat.Odd)+1)
            Rlati = NaN;
            Rloni = NaN;
          else
            % If most recent packet is odd then i=1, or vice versa.
            i = uint8(packet.AirbornePosition.CPRFormat);
            if i == 1
              Rlati = Rlat1;
            else
              Rlati = Rlat0;
            end
            
            ni = max(NL(i+1,1)-double(i), 1);
            Dloni = 360 / ni;
            
            % Longitude index, m
            m = floor(XZper(uint8(ADSBCPRFormat.Even)+1,1)...
              *(NL(i+1,1)-1)-XZper(uint8(ADSBCPRFormat.Odd)+1,1)*NL(i+1,1)+0.5);
            
            Rloni = Dloni*(m+XZper(i+1,1));
          end
        end
      end
      
      if ~isnan(Rlati)
        savePositionPacket(obj,packet.ICAO24,Rlati,Rloni);
      end
      
      packet.AirbornePosition.Longitude = Rloni;
      packet.AirbornePosition.Latitude = Rlati;
    end
    
    function [savedLat,savedLon,jSaved1,jSaved2,mSaved1,mSaved2] = ...
        getSavedPosition(obj, aircraftID)
      %getSavedPosition Search saved aircraft positions
      %   [LAT,LON,J1,J2,M1,M2]=getSavedPosition(ID,ADSB) returns saved position
      %   for ICAO24 ID, ID. ADSB contains the configuration information for the
      %   ADS-B receiver. LAT and LON are last known latitude and longitude,
      %   respectively. J1 and J2 are partial information on latitude zone number
      %   based on LAT. M1 and M2 are partial information on longitude zone
      %   number based on LON.
      
      database = obj.PositionDatabase;
      
      idx = database.ID==hex2dec(aircraftID);
      if all(~idx)
        savedLat = NaN;
        savedLon = NaN;
        jSaved1 = [0 0];
        jSaved2 = [0 0];
        mSaved1 = [0 0];
        mSaved2 = [0 0];
      else
        savedData = database.ZoneData(:,idx);
        savedPos = database.Position(:,idx);
        
        savedLat = savedPos(1,1);
        savedLon = savedPos(2,1);
        jSaved1 = savedData(1:2,1);
        jSaved2 = savedData(3:4,1);
        mSaved1 = savedData(5:6,1);
        mSaved2 = savedData(7:8,1);
      end
    end
    
    function [lat,lon]=...
        getPositionPacket(obj, aircraftID,cprFormat,rcvTime)
      
      lat = NaN;
      lon = NaN;
      
      database = obj.PositionPacketDatabase;
      idx = find(database.ID==hex2dec(aircraftID),1,'first');
      if ~isempty(idx)
        % Check CPR format
        if (database.CPRFormat(1,idx(1)) == cprFormat)
          
          % Check time
          savedTime = database.Time(1,idx(1));
          elapsedTime = (rcvTime - savedTime);
          if elapsedTime < 10
            lat = database.Latitude(:,idx(1));
            lon = database.Longitude(:,idx(1));
          end
        end
      end
    end
    
    function setPositionPacket(obj,aircraftID,cprFormat,rcvTime,lat,lon)
      
      database = obj.PositionPacketDatabase;
      idIdx = find(database.ID==hex2dec(aircraftID),1,'first');
      if any(idIdx)
        % We already have a record of this aircraft
        idx = idIdx;
      else
        % Aircraft is not in the data base
        [~,oldestIdx] = min(database.Time);
        idx = oldestIdx;
        database.ID(1,idx) = hex2dec(aircraftID);
      end
      database.Latitude(:,idx) = lat;
      database.Longitude(:,idx) = lon;
      database.CPRFormat(1,idx) = cprFormat;
      database.Time(1,idx) = rcvTime;
      obj.PositionPacketDatabase = database;
    end
    
    function savePositionPacket(obj, aircraftID,lat,lon)
      %savePositionPacket Save last know position
      %   savePositionPacket(ID,LAT,LON,ADSB) save the last known latitude, LAT,
      %   and longitude, LON, position of aircraft, ID, in the PositionDatabase
      %   field of ADSB and returns the updated ADSB config structure.
      
      jSaved1 = coder.nullcopy(zeros(2,1));
      jSaved2 = coder.nullcopy(zeros(2,1));
      mSaved1 = coder.nullcopy(zeros(2,1));
      mSaved2 = coder.nullcopy(zeros(2,1));
      idx = coder.nullcopy(0);
      
      database = obj.PositionDatabase;
      
      decID = hex2dec(aircraftID);
      idIdx = find(database.ID==decID,1,'first');
      if any(idIdx)
        % We already have a record of this aircraft
        idx(1) = idIdx;
      else
        % Aircraft is not in the data base
        [~,oldestIdx] = min(database.Time);
        idx(1) = oldestIdx;
        database.ID(1,idx) = decID;
      end
      
      % Latitude and longitude zone index components due to saved position as
      % defined in Section A.2.6.5 Equation (b) and (e) of [1].
      NZ = 15;
      Dlat0 = 360/(4*NZ-0);
      Dlat1 = 360/(4*NZ-1);
      % floor(lats/Dlati) of Eq. (b)
      jSaved1(1) = floor(lat / Dlat0); % Even, i==0
      jSaved1(2) = floor(lat / Dlat1); % Odd, i==1
      % mod(lats,Dlati)/Dlati of Eq. (b)
      jSaved2(1) = modDegree(lat,Dlat0) / Dlat0; % Even, i==0
      jSaved2(2) = modDegree(lat,Dlat1) / Dlat1; % Odd, i==1
      NL = helperAdsbNL(lat);
      if NL-0 > 0
        Dlon0 = 360/(NL-0);
      else
        Dlon0 = 360;
      end
      if NL-1 > 0
        Dlon1 = 360/(NL-1);
      else
        Dlon1 = 360;
      end
      % floor(lons/Dloni) of Eq. (e)
      mSaved1(1) = floor(lon / Dlon0); % Even, i==0
      mSaved1(2) = floor(lon / Dlon1); % Odd, i==1
      % mod(lons,Dloni)/Dloni of Eq. (e)
      mSaved2(1) = modDegree(lon,Dlon0) / Dlon0; % Even, i==0
      mSaved2(2) = modDegree(lon,Dlon1) / Dlon1; % Odd, i==1
      
      database.Time(1,idx) = database.Counter;
      database.Counter = database.Counter + 1;
      database.Position(:,idx) = [lat; lon];
      database.ZoneData(:,idx) = [jSaved1(1);jSaved1(2);jSaved2(1);jSaved2(2);...
        mSaved1(1);mSaved1(2);mSaved2(1);mSaved2(2)];
      
      obj.PositionDatabase = database;
    end
    
    function msg = getMessagePacket(obj,header)
      msg = obj.CachedMessagePacket;
      msg.Header = header;
    end
  end
  
  methods (Static, Hidden)
    function msg = msgPacket()
      msg.Header = helperAdsbPhyPacket();
      msg.ICAO24 = '      ';  % ICAO 24-bit aircraft ID (Hex)
      msg.TC = uint8(0);      % Type Code
      msg.AirborneVelocity = ...
        helperAdsbRxMsgParser.getVelocityPacket();
      msg.Identification = ...
        helperAdsbRxMsgParser.getIDPacket();
      msg.AirbornePosition = ...
        helperAdsbRxMsgParser.getAirbornePositionPacket();
    end
    
    function packet = getAirbornePositionPacket()
      packet = struct(...
        'Status', ADSBStatus.StatusUnset, ...
        'DiversityAntenna', false, ...
        'Altitude', 0, ...
        'UTCSynchronized', false, ...
        'CPRFormat', ADSBCPRFormat.CPRFormatUnset, ...
        'Longitude', 0, ...
        'Latitude', 0);
    end
    
    function packet = getVelocityPacket()
      %getVelocityPacket Airborne velocity packet prototype
      %   P=getVelocityPacket() returns airborne velocity packet prototype with
      %   dummy data.
      
      packet = struct(...
        'Subtype', ADSBVelocitySubtype.VelocitySubtypeUnset, ...
        'IntentChange', false, ...
        'IFRCapability', false, ...
        'VelocityUncertainty', uint8(0), ...
        'Speed', 0, ...
        'Heading', 0, ...
        'HeadingSymbol', '  ', ...
        'VerticalRateSource', false, ...
        'VerticalRate', 0, ...
        'TurnIndicator', 0, ...
        'GHD', 0);
    end
    
    function packet = getIDPacket()
      packet = struct(...
        'VehicleCategory', ADSBVehicleCategory.NoData, ...
        'FlightID', '        ');
    end
  end
end

%========================== Helper Functions ==============================
function z = modDegree(x,y)
%modDegree Modulo operation for degree values
%   Z = modDegree(X,Y) returns mod(X,Y) for X>0, and mod(X+360,Y) for X<0.

  if x < 0
    x = 360 + x;
  end
  z = mod(x,y);
end
