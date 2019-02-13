function AutoDrive:startAD(vehicle)
    vehicle.ad.isActive = true;
    vehicle.ad.creationMode = false;
    
    --vehicle.forceIsActive = true;
    vehicle.spec_motorized.stopMotorOnLeave = false;
    vehicle.spec_enterable.disableCharacterOnLeave = false;
    vehicle.currentHelper = g_helperManager:getRandomHelper()
    vehicle.spec_aiVehicle.isActive = true
    
    vehicle.ad.unloadType = AutoDrive:getCurrentFillType(vehicle);

    if vehicle.setRandomVehicleCharacter ~= nil then
        vehicle:setRandomVehicleCharacter()
    end
    
    if vehicle.steeringEnabled == true then
        vehicle.steeringEnabled = false;
    end
end;

function AutoDrive:stopAD(vehicle)
    vehicle.ad.isStopping = true;
end;

function AutoDrive:stopVehicle(vehicle, dt)
    if math.abs(vehicle.lastSpeedReal) < 0.001 then
        vehicle.ad.isStopping = false;
    end;
    
    if vehicle.ad.isStopping then
        AutoDrive:getVehicleToStop(vehicle, dt);
    else       
        vehicle.ad.currentWayPoint = 0;
        vehicle.ad.drivingForward = true;
        vehicle.ad.isActive = false;
        
        vehicle.spec_aiVehicle.isActive = false;
        vehicle.ad.isUnloading = false;
        vehicle.ad.isLoading = false;
 
        vehicle.forceIsActive = false;
        vehicle.spec_motorized.stopMotorOnLeave = true;
        vehicle.spec_enterable.disableCharacterOnLeave = true;
        vehicle.currentHelper = nil
                        
        vehicle.ad.initialized = false;
        vehicle.ad.lastSpeed = 10;
        if vehicle.steeringEnabled == false then
            vehicle.steeringEnabled = true;
        end

        vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF);
    end;
end;

function AutoDrive:getVehicleToStop(vehicle, dt)
    local finalSpeed = 0;
    local allowedToDrive = false;
    local node = vehicle.components[1].node;					
    if vehicle.getAIVehicleDirectionNode ~= nil then
        node = vehicle:getAIVehicleDirectionNode();
    end;
    local x,y,z = getWorldTranslation(vehicle.components[1].node);   
    local lx, lz = AIVehicleUtil.getDriveDirection(node, x, y, z);
    AIVehicleUtil.driveInDirection(vehicle, dt, 30, 1, 0.2, 20, allowedToDrive, vehicle.ad.drivingForward, lx, lz, finalSpeed, 1);
end;

function AutoDrive:isActive(vehicle)
    if vehicle ~= nil then
        return vehicle.ad.isActive;
    end;
    return false;
end;

function AutoDrive:detectAdTrafficOnRoute(vehicle)
	if vehicle.ad.isActive == true then
		local idToCheck = 3;
		local alreadyOnDualRoute = false;
		if vehicle.ad.wayPoints[vehicle.ad.currentWayPoint-2] ~= nil and vehicle.ad.wayPoints[vehicle.ad.currentWayPoint-1] ~= nil then
			alreadyOnDualRoute = AutoDrive:isDualRoad(vehicle.ad.wayPoints[vehicle.ad.currentWayPoint-2], vehicle.ad.wayPoints[vehicle.ad.currentWayPoint-1]);
        end;
        
		if vehicle.ad.wayPoints[vehicle.ad.currentWayPoint+idToCheck] ~= nil and vehicle.ad.wayPoints[vehicle.ad.currentWayPoint+idToCheck+1] ~= nil and not alreadyOnDualRoute then
			local dualRoute = AutoDrive:isDualRoad(vehicle.ad.wayPoints[vehicle.ad.currentWayPoint+idToCheck], vehicle.ad.wayPoints[vehicle.ad.currentWayPoint+idToCheck+1]);
			
			local dualRoutePoints = {};
			local counter = 0;
			idToCheck = -3;
            while (dualRoute == true) or (idToCheck < 3) do
                local startNode = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint+idToCheck];
                local targetNode = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint+idToCheck+1];
				if (startNode ~= nil) and (targetNode ~= nil) then
                    local testDual = AutoDrive:isDualRoad(startNode, targetNode)					
					if testDual == true then
						counter = counter + 1;
						dualRoutePoints[counter] = startNode.id;
						dualRoute = true;
					else
						dualRoute = false;
					end;
				end;
				idToCheck = idToCheck + 1;
			end;

			local trafficDetected = false;
			vehicle.ad.trafficVehicle = nil;
			if counter > 0 then
				for _,other in pairs(g_currentMission.vehicles) do
					if other ~= vehicle and other.ad ~= nil and other.ad.isActive == true then
						local onSameRoute = false;
						local window = 4;
						local i = -window;
						while i <= window do
							if other.ad.wayPoints[other.ad.currentWayPoint+i] ~= nil then
								for _,point in pairs(dualRoutePoints) do
									if point == other.ad.wayPoints[other.ad.currentWayPoint+i].id then
										onSameRoute = true;
									end;
								end;
							end;
							i = i + 1;
						end;
						if onSameRoute == true and other.ad.trafficVehicle == nil then
							trafficDetected = true;
							vehicle.ad.trafficVehicle = other;
						end;
					end;
				end;
			end;
			if trafficDetected == true then
				--print("Traffic on same road deteced");
				return true;
			end;

		end;

	end;
	return false;

end

function AutoDrive:detectTraffic(vehicle, wp_next)
	local x,y,z = getWorldTranslation( vehicle.components[1].node );
	--create bounding box to check for vehicle
	local x1,y1,z1 = getWorldTranslation(vehicle.components[1].node);
	local rx,ry,rz = localDirectionToWorld(vehicle.components[1].node, 0,0,1);
	local vehicleVector = {x= math.sin(rx) ,z= math.sin(rz) };
	local width = vehicle.sizeWidth;
	local length = vehicle.sizeLength;
	local ortho = { x=-vehicleVector.z, z=vehicleVector.x };
	local lookAheadDistance = math.min(vehicle.lastSpeedReal*3600/40, 1) * 10 + 2;
	local boundingBox = {};
    boundingBox[1] ={ 	x = x + (width/2) * ortho.x,
                        y = y,
						z = z + (width/2) * ortho.z};
	boundingBox[2] ={ 	x = x - (width/2) * ortho.x,
                        y = y,
						z = z - (width/2) * ortho.z};
	boundingBox[3] ={ 	x = x - (width/2) * ortho.x +  (length/2 + lookAheadDistance) * vehicleVector.x,
                        y = y,
						z = z - (width/2) * ortho.z +  (length/2 + lookAheadDistance) * vehicleVector.z };
	boundingBox[4] ={ 	x = x + (width/2) * ortho.x +  (length/2 + lookAheadDistance) * vehicleVector.x,
                        y = y,
						z = z + (width/2) * ortho.z +  (length/2 + lookAheadDistance) * vehicleVector.z};

	
    --AutoDrive:drawLine(boundingBox[1], boundingBox[2], newColor(0,0,0,1));
    --AutoDrive:drawLine(boundingBox[2], boundingBox[3], newColor(0,0,0,1));
    --AutoDrive:drawLine(boundingBox[3], boundingBox[4], newColor(0,0,0,1));
    --AutoDrive:drawLine(boundingBox[4], boundingBox[1], newColor(0,0,0,1));	

	for _,other in pairs(g_currentMission.vehicles) do --pairs(g_currentMission.nodeToVehicle) do
		if other ~= vehicle then
			local isAttachedToMe = false;

			for _i,impl in pairs(vehicle:getAttachedImplements()) do
				if impl.object ~= nil then
					if impl.object == other then isAttachedToMe = true; end;
                    
					if impl.object.getAttachedImplements ~= nil then
						for _, implement in pairs(impl.object:getAttachedImplements()) do
							if implement.object == other then isAttachedToMe = true; end;
						end;
					end;
				end;
            end;
            
			if isAttachedToMe == false and other.components ~= nil then
				if other.sizeWidth == nil then
					--print("vehicle " .. other.configFileName .. " has no width");
				else
					if other.sizeLength == nil then
						--print("vehicle " .. other.configFileName .. " has no length");
					else
						if other.rootNode == nil then
							--print("vehicle " .. other.configFileName .. " has no root node");
						else

							local otherWidth = other.sizeWidth;
							local otherLength = other.sizeLength;
							local otherPos = {};
							otherPos.x,otherPos.y,otherPos.z = getWorldTranslation( other.components[1].node ); 

							local rx,ry,rz = localDirectionToWorld(other.components[1].node, 0, 0, 1);

							local otherVectorToWp = {};
							otherVectorToWp.x = rx;
							otherVectorToWp.z = rz;

							local otherPos2 = {};
							otherPos2.x = otherPos.x + (otherLength/2) * (otherVectorToWp.x/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z)));
							otherPos2.y = y;
							otherPos2.z = otherPos.z + (otherLength/2) * (otherVectorToWp.z/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z)));
							local otherOrtho = { x=-otherVectorToWp.z, z=otherVectorToWp.x };

							local otherBoundingBox = {};
                            otherBoundingBox[1] ={ 	x = otherPos.x + (otherWidth/2) * ( otherOrtho.x / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) + (otherLength/2) * (otherVectorToWp.x/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z))),
                                                    y = y,
													z = otherPos.z + (otherWidth/2) * ( otherOrtho.z / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) + (otherLength/2) * (otherVectorToWp.z/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z)))};

							otherBoundingBox[2] ={ 	x = otherPos.x - (otherWidth/2) * ( otherOrtho.x / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) + (otherLength/2) * (otherVectorToWp.x/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z))),
                                                    y = y,
                                                    z = otherPos.z - (otherWidth/2) * ( otherOrtho.z / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) + (otherLength/2) * (otherVectorToWp.z/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z)))};
							otherBoundingBox[3] ={ 	x = otherPos.x - (otherWidth/2) * ( otherOrtho.x / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) - (otherLength/2) * (otherVectorToWp.x/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z))),
                                                    y = y,
                                                    z = otherPos.z - (otherWidth/2) * ( otherOrtho.z / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) - (otherLength/2) * (otherVectorToWp.z/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z)))};

							otherBoundingBox[4] ={ 	x = otherPos.x + (otherWidth/2) * ( otherOrtho.x / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) - (otherLength/2) * (otherVectorToWp.x/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z))),
                                                    y = y,
                                                    z = otherPos.z + (otherWidth/2) * ( otherOrtho.z / (math.abs(otherOrtho.x)+math.abs(otherOrtho.z))) - (otherLength/2) * (otherVectorToWp.z/(math.abs(otherVectorToWp.x)+math.abs(otherVectorToWp.z)))};

							
                            --AutoDrive:drawLine(otherBoundingBox[1], otherBoundingBox[2], newColor(0,0,1,1));
                            --AutoDrive:drawLine(otherBoundingBox[2], otherBoundingBox[3], newColor(0,0,1,1));
                            --AutoDrive:drawLine(otherBoundingBox[3], otherBoundingBox[4], newColor(0,0,1,1));
                            --AutoDrive:drawLine(otherBoundingBox[4], otherBoundingBox[1], newColor(0,0,1,1));							

							if AutoDrive:BoxesIntersect(boundingBox, otherBoundingBox) == true then
								if other.configFileName ~= nil then
									--print("vehicle " .. vehicle.configFileName .. " has collided with " .. other.configFileName);
								else
									if other.getName ~= nil then
										--print("vehicle " .. vehicle.configFileName .. " has collided with " .. other.getName());
									else
										--print("vehicle " .. vehicle.configFileName .. " has collided with " .. "unknown");
									end;
								end;
								return true;
							end;

						end;
					end;
				end;
			end;
		end;
	end;

	return false;
end