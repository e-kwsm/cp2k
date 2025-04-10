!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

MODULE qs_fb_trial_fns_types

#include "./base/base_uses.f90"
   IMPLICIT NONE

   PRIVATE

! public types
   PUBLIC :: fb_trial_fns_obj

! public methods
!API
   PUBLIC :: fb_trial_fns_retain, &
             fb_trial_fns_release, &
             fb_trial_fns_nullify, &
             fb_trial_fns_associate, &
             fb_trial_fns_has_data, &
             fb_trial_fns_create, &
             fb_trial_fns_get, &
             fb_trial_fns_set

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_fb_trial_fns_types'

! **************************************************************************************************
!> \brief data containing information on trial functions used by filter
!>        matrix diagonalisation method
!> \param nfunctions : nfunctions(ikind) = number of trial functions for
!>                     atomic kind ikind
!> \param functions  : functions(itrial,ikind) = the index of the
!>                     GTO atomic orbital corresponding to itrial-th trial
!>                     function for kind ikind
!> \param ref_count  : reference counter for the object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   TYPE fb_trial_fns_data
      INTEGER :: ref_count = -1
      INTEGER, DIMENSION(:), POINTER :: nfunctions => NULL()
      INTEGER, DIMENSION(:, :), POINTER :: functions => NULL()
   END TYPE fb_trial_fns_data

! **************************************************************************************************
!> \brief the object container which allows for the creation of an array
!>        of pointers to fb_trial_fns objects
!> \param obj : pointer to the fb_trial_fns object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   TYPE fb_trial_fns_obj
      TYPE(fb_trial_fns_data), POINTER, PRIVATE :: obj => NULL()
   END TYPE fb_trial_fns_obj

CONTAINS

! **************************************************************************************************
!> \brief retains given object
!> \brief ...
!> \param trial_fns : the fb_trial_fns object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_retain(trial_fns)
      ! note INTENT(IN) is okay because the obj pointer contained in the
      ! obj type will not be changed
      TYPE(fb_trial_fns_obj), INTENT(IN)                 :: trial_fns

      CPASSERT(ASSOCIATED(trial_fns%obj))
      CPASSERT(trial_fns%obj%ref_count > 0)
      trial_fns%obj%ref_count = trial_fns%obj%ref_count + 1
   END SUBROUTINE fb_trial_fns_retain

! **************************************************************************************************
!> \brief releases given object
!> \brief ...
!> \param trial_fns : the fb_trial_fns object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_release(trial_fns)
      TYPE(fb_trial_fns_obj), INTENT(INOUT)              :: trial_fns

      IF (ASSOCIATED(trial_fns%obj)) THEN
         CPASSERT(trial_fns%obj%ref_count > 0)
         trial_fns%obj%ref_count = trial_fns%obj%ref_count - 1
         IF (trial_fns%obj%ref_count == 0) THEN
            trial_fns%obj%ref_count = 1
            IF (ASSOCIATED(trial_fns%obj%nfunctions)) THEN
               DEALLOCATE (trial_fns%obj%nfunctions)
            END IF
            IF (ASSOCIATED(trial_fns%obj%functions)) THEN
               DEALLOCATE (trial_fns%obj%functions)
            END IF
            trial_fns%obj%ref_count = 0
            DEALLOCATE (trial_fns%obj)
         END IF
      ELSE
         NULLIFY (trial_fns%obj)
      END IF
   END SUBROUTINE fb_trial_fns_release

! **************************************************************************************************
!> \brief nullifies the content of given object
!> \param trial_fns : the fb_trial_fns object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_nullify(trial_fns)
      TYPE(fb_trial_fns_obj), INTENT(INOUT)              :: trial_fns

      NULLIFY (trial_fns%obj)
   END SUBROUTINE fb_trial_fns_nullify

! **************************************************************************************************
!> \brief associates the content of an object to that of another object
!>        of the same type
!> \param a : the output object
!> \param b : the input object
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_associate(a, b)
      TYPE(fb_trial_fns_obj), INTENT(OUT)                :: a
      TYPE(fb_trial_fns_obj), INTENT(IN)                 :: b

      a%obj => b%obj
   END SUBROUTINE fb_trial_fns_associate

! **************************************************************************************************
!> \brief check if the object has data associated to it
!> \param trial_fns : the fb_trial_fns object in question
!> \return : true if trial_fns%obj is associated, false otherwise
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   FUNCTION fb_trial_fns_has_data(trial_fns) RESULT(res)
      TYPE(fb_trial_fns_obj), INTENT(IN)                 :: trial_fns
      LOGICAL                                            :: res

      res = ASSOCIATED(trial_fns%obj)
   END FUNCTION fb_trial_fns_has_data

! **************************************************************************************************
!> \brief creates an fb_trial_fns object and initialises it
!> \param trial_fns : the fb_trial_fns object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_create(trial_fns)
      TYPE(fb_trial_fns_obj), INTENT(INOUT)              :: trial_fns

      CPASSERT(.NOT. ASSOCIATED(trial_fns%obj))
      ALLOCATE (trial_fns%obj)
      NULLIFY (trial_fns%obj%nfunctions)
      NULLIFY (trial_fns%obj%functions)
      trial_fns%obj%ref_count = 1
   END SUBROUTINE fb_trial_fns_create

! **************************************************************************************************
!> \brief initialises an fb_trial_fns object
!> \param trial_fns : the fb_trial_fns object in question
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_init(trial_fns)
      TYPE(fb_trial_fns_obj), INTENT(INOUT)              :: trial_fns

      CPASSERT(ASSOCIATED(trial_fns%obj))
      ! if halo_atoms are associated, then deallocate and de-associate
      IF (ASSOCIATED(trial_fns%obj%nfunctions)) THEN
         DEALLOCATE (trial_fns%obj%nfunctions)
      END IF
      IF (ASSOCIATED(trial_fns%obj%functions)) THEN
         DEALLOCATE (trial_fns%obj%functions)
      END IF
   END SUBROUTINE fb_trial_fns_init

! **************************************************************************************************
!> \brief get values of the attributes of a fb_trial_fns object
!> \param trial_fns  : the fb_trial_fns object in question
!> \param nfunctions : outputs pointer to trial_fns%obj%nfunctions
!> \param functions  : outputs pointer to trial_fns%obj%functions
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_get(trial_fns, &
                               nfunctions, &
                               functions)
      TYPE(fb_trial_fns_obj), INTENT(IN)                 :: trial_fns
      INTEGER, DIMENSION(:), OPTIONAL, POINTER           :: nfunctions
      INTEGER, DIMENSION(:, :), OPTIONAL, POINTER        :: functions

      CPASSERT(ASSOCIATED(trial_fns%obj))
      IF (PRESENT(nfunctions)) nfunctions => trial_fns%obj%nfunctions
      IF (PRESENT(functions)) functions => trial_fns%obj%functions
   END SUBROUTINE fb_trial_fns_get

! **************************************************************************************************
!> \brief sets the attributes of a fb_trial_fns object
!> \param trial_fns  : the fb_trial_fns object in question
!> \param nfunctions : associates trial_fns%obj%nfunctions to this pointer
!> \param functions  : associates trial_fns%obj%nfunctions to this pointer
!> \author Lianheng Tong (LT) lianheng.tong@kcl.ac.uk
! **************************************************************************************************
   SUBROUTINE fb_trial_fns_set(trial_fns, &
                               nfunctions, &
                               functions)
      TYPE(fb_trial_fns_obj), INTENT(INOUT)              :: trial_fns
      INTEGER, DIMENSION(:), OPTIONAL, POINTER           :: nfunctions
      INTEGER, DIMENSION(:, :), OPTIONAL, POINTER        :: functions

      CPASSERT(ASSOCIATED(trial_fns%obj))
      IF (PRESENT(nfunctions)) THEN
         IF (ASSOCIATED(trial_fns%obj%nfunctions)) THEN
            DEALLOCATE (trial_fns%obj%nfunctions)
         END IF
         trial_fns%obj%nfunctions => nfunctions
      END IF
      IF (PRESENT(functions)) THEN
         IF (ASSOCIATED(trial_fns%obj%functions)) THEN
            DEALLOCATE (trial_fns%obj%functions)
         END IF
         trial_fns%obj%functions => functions
      END IF
   END SUBROUTINE fb_trial_fns_set

END MODULE qs_fb_trial_fns_types
