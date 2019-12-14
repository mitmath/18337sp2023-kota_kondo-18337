#!/usr/bin/env python

#Jesus Tordesillas Torres, December 2019

import rospy
from faster_msgs.msg import Mode
from acl_msgs.msg import QuadGoal, State
from geometry_msgs.msg import Pose
from behavior_selector.srv import MissionModeChange
import math

def quat2yaw(q):
    yaw = math.atan2(2 * (q.w * q.z + q.x * q.y),
                     1 - 2 * (q.y * q.y + q.z * q.z))
    return yaw

class Behavior_Selector:

    def __init__(self):
        self.mode=Mode();
        self.pose = Pose();
        self.mode.mode=self.mode.ON_GROUND
        self.pubGoal = rospy.Publisher('goal', QuadGoal, queue_size=1)
        self.pubMode = rospy.Publisher("fastermode",Mode,queue_size=1,latch=True)

        self.alt_ground = 0; #Altitude of the ground
        self.initialized=False;


    def stateCB(self, data):
        self.pose.position.x = data.pos.x
        self.pose.position.y = data.pos.y
        self.pose.position.z = data.pos.z
        self.pose.orientation = data.quat

        if(self.initialized==False):
            self.initialized=True

    #Called when buttom pressed in the interface
    def srvCB(self,req):
        if(self.initialized==False):
            print "Not initialized yet"
            return

        if req.mode == req.START and self.mode.mode==self.mode.ON_GROUND:
            print "Taking off"
            self.takeOff()

        if req.mode == req.KILL:
            print "Killing"
            self.kill()

        if req.mode == req.END and self.mode.mode==self.mode.GO:
            print "Landing"
            self.land()


    def sendMode(self):
        self.mode.header.stamp = rospy.get_rostime()
        self.pubMode.publish(self.mode)


    def takeOff(self):
        actual_position=self.pose.position;
        goal=QuadGoal();
        goal.pos.x = actual_position.x;
        goal.pos.y = actual_position.y;
        goal.pos.z = actual_position.z;

        while(goal.pos.z<=actual_position.z + 1):
            goal.pos.z = goal.pos.z+0.0035;
            self.sendGoal(goal)

        self.mode.mode=self.mode.GO
        self.sendMode();

    def land(self):
        actual_position=self.pose.position;
        goal=QuadGoal();
        goal.pos.x = actual_position.x;
        goal.pos.y = actual_position.y;
        goal.pos.z = actual_position.z;

        while(goal.pos.z>=self.alt_ground):
            goal.pos.z = goal.pos.z-0.0035;
            self.sendGoal(goal)
        #Kill motors once we are on the ground
        self.kill()

    def kill(self):
        goal=QuadGoal();
        goal.cut_power=True
        self.sendGoal(goal)
        self.mode.mode=self.mode.ON_GROUND
        self.sendMode()

    def sendGoal(self, goal):
        goal.yaw = quat2yaw(self.pose.orientation)
        goal.header.stamp = rospy.get_rostime()
        self.pubGoal.publish(goal)

                  
def startNode():
    c = Behavior_Selector()
    s = rospy.Service("/change_mode",MissionModeChange,c.srvCB)
    rospy.Subscriber("state", State, c.stateCB)
    rospy.spin()

if __name__ == '__main__':
    rospy.init_node('behavior_selector')  
    startNode()
    print "Behavior selector started" 