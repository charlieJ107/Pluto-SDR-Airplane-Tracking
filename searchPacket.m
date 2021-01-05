function [packetSamples,packetCnt,syncTimeVec] = ...
  searchPacket(xFilt, xBuff, adsbParam)
%helperAdsbRxPhyPacketSearch ADS-B receiver packet searcher
%   [PKT,CNT,ST] = helperAdsbRxPhyPacketSearch(XF,XB,ADSB) searches the
%   received signal, XB, for Mode-S packets. XF is the correlation of XB
%   with the known preamble sequence. PKT is a matrix of received samples
%   where each column is a Mode-S packet synchronized to the first
%   modulated sample. CNT is the number of valid packets in PKT. ST is a
%   vector of delay values in samples that represent the reception time of
%   each packet in PKT with respect to the beginning of, X.
%
%   See also ADSBExample, helperAdsbRxPhy, helperAdsbRxPhySync.

%   Copyright 2015-2016 The MathWorks, Inc.

%#codegen

spc = adsbParam.SamplesPerChip;
syncLen = adsbParam.SyncSequenceLength;
syncSigLen = syncLen*spc;
packetCnt = 0;
xLen = length(xBuff);
subFrameLen = adsbParam.MaxPacketLength;
subFrameDownLen = subFrameLen / adsbParam.SyncDownSampleFactor;
numSubFrames = int32(xLen / subFrameLen);

packetSamples = coder.nullcopy(zeros(adsbParam.LongPacketLength,...
 adsbParam.MaxNumPacketsInFrame,'like',xBuff));
syncTimeVec = coder.nullcopy(zeros(adsbParam.MaxNumPacketsInFrame,1));

for p=0:numSubFrames-2
  % Find the peak correlation location
  [~,tmp] = max(xFilt(p*subFrameDownLen+(1:subFrameDownLen)));
  syncIdx = int32(tmp);
  
  % Remove filter delay
  syncTime = int32(syncIdx*adsbParam.SyncDownSampleFactor-syncSigLen...
    +p*subFrameLen);
  
  % If the packet is fully contained within the received signal, X, then
  % validate.
  if (syncTime > 0) && (syncTime+(adsbParam.MaxPacketLength-1) <= xLen)
    % Construct received sync sequence
    rxSyncSignal = xBuff(syncTime+(0:syncSigLen-1));
    rxSyncSeq = ...
      sum(reshape(rxSyncSignal, spc, syncLen),1);
    
    % Check if this is a valid sync sequence. Get a threshold value based on
    % assumed high and low locations.
    highValue = sum(rxSyncSeq(adsbParam.SyncSequenceHighIndices))...
      /adsbParam.SyncSequenceNumHighValues;
    lowValue = sum(rxSyncSeq(adsbParam.SyncSequenceLowIndices))...
      /adsbParam.SyncSequenceNumLowValues;
    th = (highValue+lowValue)/2;
    
    if all(xor((rxSyncSeq < th), adsbParam.SyncSequence))
      % If the sequence matches, this is a valid preamble location
      packetCnt = packetCnt + 1;
      if packetCnt <= adsbParam.MaxNumPacketsInFrame
        % Store it only if there is space in the constant size output
        % matrix
        dataIndices = int32(adsbParam.PreambleLength...
          +(0:adsbParam.LongPacketLength-1));
        packetSamples(1:adsbParam.LongPacketLength,packetCnt) = ...
          xBuff(syncTime+dataIndices,1);
        syncTimeVec(packetCnt,1) = syncTime;
      end
    end
  end
end
end