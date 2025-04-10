!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief - to decrease the used memory size, just actual needed tree elements
!>        should be stored in memory, other ones should be written out in file
!>        - sub tree elements can be canceled and further deallocated when no
!>          global tree element refers to it anymore
!>        - then also the ongoing calculation of these elements is not needed
!>          anymore => can be canceled
!>        - MODULE: creates and handles a list of tree nodes
!>                    which can be canceled
!>                  these elements are collected and canceled all in one
!>                    from the master routine
!>        - the actual cancelation routine is implemented in master module and
!>          communication is done using the message module
!> \par History
!>      11.2012 created [Mandes Schoenherr]
!> \author Mandes
! **************************************************************************************************

MODULE tmc_cancelation
   USE cp_log_handling,                 ONLY: cp_to_string
   USE tmc_dot_tree,                    ONLY: create_dot_color
   USE tmc_tree_types,                  ONLY: &
        add_to_list, elem_list_type, status_accepted, status_accepted_result, &
        status_calc_approx_ener, status_calculate_MD, status_calculate_NMC_steps, &
        status_calculate_energy, status_calculated, status_cancel_ener, status_cancel_nmc, &
        status_canceled_ener, status_canceled_nmc, status_created, status_deleted, &
        status_deleted_result, status_rejected, status_rejected_result, tree_type
   USE tmc_types,                       ONLY: tmc_env_type
#include "../base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'tmc_cancelation'

   PUBLIC :: add_to_canceling_list, free_cancelation_list

CONTAINS

! **************************************************************************************************
!> \brief add a certain element to the cancelation list
!> \param elem the sub tree element, to be added
!> \param tmc_env tmc environment
!> \author Mandes 11.2012
! **************************************************************************************************
   SUBROUTINE add_to_canceling_list(elem, tmc_env)
      TYPE(tree_type), POINTER                           :: elem
      TYPE(tmc_env_type), POINTER                        :: tmc_env

      CHARACTER(LEN=*), PARAMETER :: routineN = 'add_to_canceling_list'

      INTEGER                                            :: handle
      LOGICAL                                            :: need_to_cancel

      CPASSERT(ASSOCIATED(elem))
      CPASSERT(ASSOCIATED(tmc_env))
      CPASSERT(ASSOCIATED(tmc_env%m_env))
      CPASSERT(ASSOCIATED(tmc_env%params))

      ! start the timing
      CALL timeset(routineN, handle)

      IF (tmc_env%params%SPECULATIVE_CANCELING) THEN
         need_to_cancel = .FALSE.
         ! update status
         SELECT CASE (elem%stat)
         CASE (status_calculate_energy)
            elem%stat = status_cancel_ener
            need_to_cancel = .TRUE.
            tmc_env%m_env%count_cancel_ener = tmc_env%m_env%count_cancel_ener + 1
         CASE (status_calc_approx_ener) !TODO maybe elem status for approx ener cancel
            !elem%stat = status_cancel_ener
            !need_to_cancel = .TRUE.
         CASE (status_calculate_NMC_steps, status_calculate_MD)
            elem%stat = status_cancel_nmc
            need_to_cancel = .TRUE.
            tmc_env%m_env%count_cancel_NMC = tmc_env%m_env%count_cancel_NMC + 1
         CASE (status_accepted, status_accepted_result, status_rejected, &
               status_rejected_result, status_calculated, status_created, &
               status_cancel_nmc, status_cancel_ener, status_canceled_nmc, &
               status_canceled_ener)
         CASE (status_deleted_result, status_deleted)
            ! if deallocation is deactivated, should not be
            CPWARN("try to add deleted element cancelation list ")
            WRITE (*, *) "WARNING: try to cancel subtree, element ", elem%sub_tree_nr, elem%nr, ", with status ", elem%stat
         CASE DEFAULT
            CALL cp_abort(__LOCATION__, &
                          "try to add element with unknown status to cancelation list (stat=" &
                          //cp_to_string(elem%stat))
         END SELECT
         ! set dot color
         IF (tmc_env%params%DRAW_TREE) &
            CALL create_dot_color(tree_element=elem, tmc_params=tmc_env%params)

         ! add to list
         IF (need_to_cancel) THEN
            CALL add_to_list(elem=elem, list=tmc_env%m_env%cancelation_list)
         END IF
      END IF
      ! end the timing
      CALL timestop(handle)
   END SUBROUTINE add_to_canceling_list

! **************************************************************************************************
!> \brief for correct finalizing deallocate the cancelation list
!> \param cancel_list ...
!> \param
!> \author Mandes 12.2012
! **************************************************************************************************
   SUBROUTINE free_cancelation_list(cancel_list)
      TYPE(elem_list_type), POINTER                      :: cancel_list

      TYPE(elem_list_type), POINTER                      :: tmp_element

      cancel_elem_loop: DO WHILE (ASSOCIATED(cancel_list))
         tmp_element => cancel_list%next
         DEALLOCATE (cancel_list)
         cancel_list => tmp_element
      END DO cancel_elem_loop
   END SUBROUTINE free_cancelation_list

END MODULE tmc_cancelation
